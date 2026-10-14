#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Create and validate a novel project from the repository-wide project template.

Usage:
  python tools/new_novel_project.py --name 我的小说
  python tools/new_novel_project.py --name 我的小说 --slug novel-02 --activate
  python tools/new_novel_project.py --name 我的小说 --slug novel-02 --check
"""
import argparse
import re
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TEMPLATE = REPO / "项目模板"
PROJECTS = REPO / "项目"
ROUTER = REPO / "项目路由.md"
SKIP_ROOT = {"00-使用说明.md"}
TOKEN_NAME = "{{PROJECT_NAME}}"
TOKEN_SLUG = "{{PROJECT_SLUG}}"


def valid_slug(value: str) -> str:
    value = value.strip()
    if not value or value in {".", ".."} or "/" in value or "\\" in value:
        raise ValueError("项目目录名不能为空、不能是路径、不能包含斜杠。")
    if any(ch in value for ch in '<>:"|?*\x00'):
        raise ValueError("项目目录名包含不允许的字符。")
    if value.startswith(".") or value.endswith(".") or value.endswith(" "):
        raise ValueError("项目目录名不能以点开头或以点/空格结尾。")
    return value


def template_files():
    for p in sorted(TEMPLATE.rglob("*")):
        if p.is_file() and not (p.parent == TEMPLATE and p.name in SKIP_ROOT):
            yield p


def check_project(slug: str) -> bool:
    root = PROJECTS / slug
    missing = [p.relative_to(TEMPLATE).as_posix()
               for p in template_files()
               if not (root / p.relative_to(TEMPLATE)).is_file()]
    if not root.is_dir():
        print(f"项目不存在：{root.relative_to(REPO)}", file=sys.stderr)
        return False
    if missing:
        print("项目缺少模板文件：", *missing, sep="\n  - ", file=sys.stderr)
        return False
    print(f"结构完整：{root.relative_to(REPO)}")
    return True


def activate(slug: str) -> None:
    if not ROUTER.is_file():
        raise RuntimeError("找不到仓库根目录项目路由.md")
    src = ROUTER.read_text(encoding="utf-8")
    replaced, count = re.subn(
        r"(?m)^PROJECT_ROOT\s*=\s*项目/[^\r\n]+$",
        "PROJECT_ROOT = 项目/" + slug,
        src,
    )
    if count != 1:
        raise RuntimeError("项目路由中缺少唯一PROJECT_ROOT行；没有修改路由。")
    ROUTER.write_text(replaced, encoding="utf-8")
    print(f"已切换活跃项目：项目/{slug}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--name", required=True, help="新小说的显示名称")
    parser.add_argument("--slug", help="目录名称；默认与--name相同")
    parser.add_argument("--activate", action="store_true", help="创建后切换默认作品")
    parser.add_argument("--check", action="store_true", help="仅检查已有作品结构")
    args = parser.parse_args()
    name = args.name.strip()
    if not name:
        parser.error("--name不能为空")
    try:
        slug = valid_slug(args.slug or name)
    except ValueError as e:
        parser.error(str(e))
    root = PROJECTS / slug
    if args.check:
        return 0 if check_project(slug) else 1
    if not TEMPLATE.is_dir():
        parser.error(f"模板不存在：{TEMPLATE}")
    if root.exists():
        parser.error(f"目标项目已经存在，拒绝覆盖：{root}")
    sources = list(template_files())
    if not sources:
        parser.error("项目模板中没有文件")
    PROJECTS.mkdir(parents=True, exist_ok=True)
    try:
        for src in sources:
            relative = src.relative_to(TEMPLATE)
            dest = root / relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            if src.suffix.lower() in {".md", ".txt", ".json", ".yaml", ".yml"}:
                text = src.read_text(encoding="utf-8")
                text = text.replace(TOKEN_NAME, name).replace(TOKEN_SLUG, slug)
                dest.write_text(text, encoding="utf-8")
            else:
                shutil.copy2(src, dest)
    except Exception:
        shutil.rmtree(root, ignore_errors=True)
        raise
    print(f"已创建小说项目：{root.relative_to(REPO)}，共 {len(sources)} 个模板文件")
    if not check_project(slug):
        return 1
    if args.activate:
        activate(slug)
    print("下一步：填写项目说明；根据工作流开始阶段一问答、证据编译与正式资料确认。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
