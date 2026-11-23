# EFF large word list — attribution and pinned provenance

File: `eff-large.txt`, unchanged bytes (dice indices and words retained).
Copyright © 2016 Electronic Frontier Foundation (EFF); word list by Joseph Bonneau / EFF.
License: Creative Commons Attribution 3.0 Unported (CC BY 3.0).
License link: https://creativecommons.org/licenses/by/3.0/
Legal code: https://creativecommons.org/licenses/by/3.0/legalcode
Original: https://www.eff.org/files/2016/07/18/eff_large_wordlist.txt
License attribution documented by mirror: `ulif/diceware`, COPYRIGHT
(points to https://www.eff.org/copyright).

Retrieved via GitHub API from the data-only mirror:
https://github.com/ulif/diceware/blob/b3138e95ee4054f579b52baf269eec4f68a6b9a7/diceware/wordlists/wordlist_en_eff.txt
Mirror copyright notice:
https://github.com/ulif/diceware/blob/b3138e95ee4054f579b52baf269eec4f68a6b9a7/COPYRIGHT
No Python implementation from that GPL project is copied or imported.

Pinned bytes: 108800; 7776 unique words, five base-6 dice digits per entry.
SHA-256: addd35536511597a02fa0a9ff1e5284677b8883b83e986e43f15a3db996b903e

No word-list modifications. VIC-A generation code selects six words independently
with replacement using libsodium randombytes_uniform(7776), joins with one ASCII
space and does not filter the output. Entropy of this generation procedure is
6 * log2(7776) = 77.548875... bits, assuming the CSPRNG and trusted execution.
This is not an entropy claim about manually supplied text or weak human choices.
The generation policy/list can evolve without changing how existing passwords are
normalized or used to decrypt format VICAVA02. Do not silently change NFC/KDF.
