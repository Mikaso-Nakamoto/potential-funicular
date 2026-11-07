"""Entry point used by the single-file build (agpatch.pyz)."""
import sys

from agpatch.cli import main

if __name__ == "__main__":
    sys.exit(main())
