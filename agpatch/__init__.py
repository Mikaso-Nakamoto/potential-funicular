"""agpatch — a small, reviewable region-gate patcher for Antigravity.

Design rules (all deliberate, all tested):
  * no network access, no telemetry, no auto-update
  * no self-elevation: never asks for sudo/UAC, never kills processes
  * every write is preceded by a pristine backup and followed by verification
  * unknown versions are refused, never guessed
"""

__version__ = "0.1.0"
