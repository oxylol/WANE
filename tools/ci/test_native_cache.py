#!/usr/bin/env python3
"""Test of ci/native_cache.sh and the cache half of ci/setup_godot_cpp.sh: python3 tools/ci/test_native_cache.py

Where the shared native build cache lives, what keys it, how it is pruned, and that a worktree
clones godot-cpp from the cache without the network (docs/adr/0021, "Shared build cache").
"""

from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
GIT = ["git", "-c", "user.name=t", "-c", "user.email=t@t", "-c", "commit.gpgsign=false"]


def run(args: list[str], cwd: Path, env: dict[str, str] | None = None) -> str:
    done = subprocess.run(args, cwd=cwd, env=env, capture_output=True, text=True, check=False)
    if done.returncode != 0:
        raise AssertionError(f"{args} failed ({done.returncode}): {done.stderr}")
    return done.stdout.strip()


def sh(script: str, cwd: Path, **env: str) -> str:
    """Runs `script` in bash with ci/native_cache.sh sourced, in `cwd`, with only `env` set from
    the cache's variables (the caller's own are removed)."""
    clean = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith("WANE_NATIVE") and k not in ("CI", "GITHUB_ACTIONS", "CXX")
    }
    clean.update(env)
    return run(["bash", "-c", f". '{ROOT}/ci/native_cache.sh'; {script}"], cwd, clean)


class Location(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="wane-cache-test-")).resolve()
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def make_repo(self) -> tuple[Path, Path]:
        """A git repository with a commit and a worktree of it; returns (main, worktree)."""
        main = self.tmp / "main"
        main.mkdir()
        run(GIT + ["init", "-q", "."], main)
        (main / "a").write_text("a")
        run(GIT + ["add", "a"], main)
        run(GIT + ["commit", "-q", "-m", "a"], main)
        tree = self.tmp / "tree"
        run(GIT + ["worktree", "add", "-q", "--detach", str(tree)], main)
        return main, tree

    def test_an_explicit_folder_wins_and_off_means_no_cache(self) -> None:
        self.assertEqual(
            sh("native_cache_dir", self.tmp, WANE_NATIVE_CACHE="/some/where"), "/some/where"
        )
        for word in ("off", "none", "0", "false"):
            self.assertEqual(sh("native_cache_dir", self.tmp, WANE_NATIVE_CACHE=word), "", word)

    def test_every_worktree_of_a_repository_shares_the_folder_in_the_main_gits_dir(self) -> None:
        main, tree = self.make_repo()
        want = str(main / ".git" / "wane-native-cache")
        self.assertEqual(sh("native_cache_dir", main), want)
        self.assertEqual(sh("native_cache_dir", tree), want)
        self.assertEqual(sh("native_cache_dir", main / ".git"), want)

    def test_without_git_it_is_the_users_cache_folder(self) -> None:
        plain = self.tmp / "plain"
        plain.mkdir()
        got = sh(
            "native_cache_dir",
            plain,
            XDG_CACHE_HOME=str(self.tmp / "xdg"),
            GIT_CEILING_DIRECTORIES=str(self.tmp),
        )
        self.assertEqual(got, str(self.tmp / "xdg" / "wane" / "native"))
        got = sh(
            "native_cache_dir",
            plain,
            HOME=str(self.tmp / "home"),
            GIT_CEILING_DIRECTORIES=str(self.tmp),
        )
        self.assertEqual(got, str(self.tmp / "home" / ".cache" / "wane" / "native"))

    def test_ci_has_no_cache_unless_it_names_a_folder(self) -> None:
        main, _ = self.make_repo()
        self.assertEqual(sh("native_cache_dir", main, CI="true"), "")
        self.assertEqual(sh("native_cache_dir", main, GITHUB_ACTIONS="true"), "")
        self.assertEqual(sh("native_cache_dir", main, CI="true", WANE_NATIVE_CACHE="/x"), "/x")


class Key(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="wane-cache-key-")).resolve()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        (self.tmp / "native").mkdir()
        (self.tmp / "tools").mkdir()
        self.version(commit="a" * 40)
        (self.tmp / "tools" / "requirements.txt").write_text("SCons==4.10.1\n")
        self.bin = self.tmp / "bin"
        self.bin.mkdir()
        self.compiler("g++", "g++ (GCC) 13.2.0")

    def version(self, commit: str) -> None:
        (self.tmp / "native" / ".godot-cpp-version").write_text(f"godot-4.5-stable {commit}\n")

    def compiler(self, name: str, banner: str) -> None:
        path = self.bin / name
        path.write_text(f'#!/bin/sh\necho "{banner}"\n')
        path.chmod(0o755)

    def key(self, platform: str = "linux", arch: str = "") -> str:
        return sh(f"native_cache_key {platform} '{arch}'", self.tmp, CXX=str(self.bin / "g++"))

    def test_a_key_is_sixteen_hex_digits_and_stable(self) -> None:
        key = self.key()
        self.assertRegex(key, r"^[0-9a-f]{16}$")
        self.assertEqual(self.key(), key)

    def test_the_platform_the_arch_the_compiler_and_the_godot_cpp_commit_change_it(self) -> None:
        base = self.key()
        self.assertNotEqual(self.key(platform="windows"), base)
        self.assertNotEqual(self.key(arch="arm64"), base)
        self.compiler("g++", "g++ (GCC) 14.1.0")
        changed_compiler = self.key()
        self.assertNotEqual(changed_compiler, base)
        self.version(commit="b" * 40)
        self.assertNotEqual(self.key(), changed_compiler)

    def test_a_changed_scons_pin_changes_it(self) -> None:
        base = self.key()
        (self.tmp / "tools" / "requirements.txt").write_text("SCons==4.11.0\n")
        self.assertNotEqual(self.key(), base)


class Prune(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="wane-cache-prune-")).resolve()
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def aged(self, name: str, days: int) -> Path:
        path = self.tmp / "scons-1" / "ab" / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text("object")
        then = time.time() - days * 86400
        os.utime(path, (then, then))
        return path

    def test_files_nobody_used_for_the_limit_go_and_used_ones_stay(self) -> None:
        old = self.aged("old", 90)
        fresh = self.aged("fresh", 3)
        sh(f"native_cache_prune '{self.tmp}'", self.tmp)
        self.assertFalse(old.exists())
        self.assertTrue(fresh.exists())

    def test_empty_folders_go_with_their_files(self) -> None:
        self.aged("old", 90)
        sh(f"native_cache_prune '{self.tmp}'", self.tmp)
        self.assertFalse((self.tmp / "scons-1").exists())

    def test_the_limit_is_in_the_environment_and_a_day_passes_between_prunes(self) -> None:
        sh(f"native_cache_prune '{self.tmp}'", self.tmp)
        self.assertTrue((self.tmp / ".pruned").exists())
        old = self.aged("old", 90)
        sh(f"native_cache_prune '{self.tmp}'", self.tmp)
        self.assertTrue(old.exists(), "pruned again within a day")
        os.utime(self.tmp / ".pruned", (time.time() - 2 * 86400,) * 2)
        sh(f"native_cache_prune '{self.tmp}'", self.tmp, WANE_NATIVE_CACHE_DAYS="200")
        self.assertTrue(old.exists(), "90 days is inside a limit of 200")
        os.utime(self.tmp / ".pruned", (time.time() - 2 * 86400,) * 2)
        sh(f"native_cache_prune '{self.tmp}'", self.tmp, WANE_NATIVE_CACHE_DAYS="30")
        self.assertFalse(old.exists())

    def test_a_missing_folder_is_nothing_to_do(self) -> None:
        sh(f"native_cache_prune '{self.tmp / 'none'}'", self.tmp)


class Setup(unittest.TestCase):
    """ci/setup_godot_cpp.sh in a scratch tree whose cache already holds the godot-cpp clone: the
    checkout is made from it, and GitHub is never asked (the proxy below refuses every connection).
    """

    def setUp(self) -> None:
        self.tmp = Path(tempfile.mkdtemp(prefix="wane-cache-setup-")).resolve()
        self.addCleanup(shutil.rmtree, self.tmp, True)
        upstream = self.tmp / "upstream"
        upstream.mkdir()
        run(GIT + ["init", "-q", "."], upstream)
        (upstream / "SConstruct").write_text("# godot-cpp\n")
        run(GIT + ["add", "."], upstream)
        run(GIT + ["commit", "-q", "-m", "godot-cpp"], upstream)
        run(GIT + ["tag", "godot-4.5-stable"], upstream)
        self.commit = run(["git", "rev-parse", "HEAD"], upstream)
        self.tree = self.tmp / "tree"
        (self.tree / "ci").mkdir(parents=True)
        (self.tree / "native").mkdir()
        for script in ("setup_godot_cpp.sh", "native_cache.sh"):
            shutil.copy(ROOT / "ci" / script, self.tree / "ci" / script)
        (self.tree / "native" / ".godot-cpp-version").write_text(
            f"godot-4.5-stable {self.commit}\n"
        )
        self.cache = self.tmp / "cache"
        self.cache.mkdir()
        run(
            [
                "git",
                "clone",
                "-q",
                "--bare",
                "--depth",
                "1",
                f"file://{upstream}",
                f"godot-cpp-{self.commit[:12]}.git",
            ],
            self.cache,
        )
        self.env = dict(
            os.environ,
            WANE_NATIVE_CACHE=str(self.cache),
            HTTPS_PROXY="http://127.0.0.1:9",
            HTTP_PROXY="http://127.0.0.1:9",
        )

    def test_a_worktree_clones_godot_cpp_from_the_cache_at_the_pinned_commit(self) -> None:
        began = time.monotonic()
        out = run(["bash", "ci/setup_godot_cpp.sh"], self.tree, self.env)
        self.assertLess(time.monotonic() - began, 10, "it asked the network")
        self.assertEqual(out.splitlines()[-1], "native/godot-cpp")
        checkout = self.tree / "native" / "godot-cpp"
        self.assertEqual(run(["git", "rev-parse", "HEAD"], checkout), self.commit)
        self.assertTrue((checkout / "SConstruct").exists())
        self.assertTrue((checkout / ".gdignore").exists())

    def test_a_second_run_leaves_the_checkout_alone(self) -> None:
        run(["bash", "ci/setup_godot_cpp.sh"], self.tree, self.env)
        marker = self.tree / "native" / "godot-cpp" / "built.os"
        marker.write_text("an object")
        run(["bash", "ci/setup_godot_cpp.sh"], self.tree, self.env)
        self.assertTrue(marker.exists())


if __name__ == "__main__":
    unittest.main()
