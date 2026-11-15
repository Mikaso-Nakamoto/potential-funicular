"""Bound new upstream description captures without manufacturing replacement text."""
import hashlib
import re

DESCRIPTION_POLICY = 'bounded-upstream-v1'
MAX_DESCRIPTION_CHARACTERS = 1000
OMISSION_REASON = 'upstream-description-too-long'
SOURCE_DESCRIPTION_POLICY = ('Repository descriptions retain their upstream language, with description_zh mirroring the same text rather than a translation. New bounded-upstream-v1 captures omit descriptions longer than 1,000 characters, retaining only length and SHA-256 evidence. Historical captures remain unchanged. No LLM-written description or individual manual review is claimed.')


def capture_description(value):
    """Preserve a short description, or only the fingerprint of an oversized one."""
    if value is None:
        value = ''
    if not isinstance(value, str):
        raise ValueError('Repository description must be text or null')
    result = {'description_en': value, 'description_zh': value,
              'description_capture_policy': DESCRIPTION_POLICY}
    if len(value) > MAX_DESCRIPTION_CHARACTERS:
        content = value.encode('utf-8')
        result.update(description_en='', description_zh='', description_omission={
            'reason': OMISSION_REASON,
            'original_characters': len(value),
            'original_utf8_bytes': len(content),
            'original_sha256': hashlib.sha256(content).hexdigest(),
            'limit_characters': MAX_DESCRIPTION_CHARACTERS,
        })
    return result


def validate_description_capture(record, errors, where):
    """Legacy captures are unchanged; marked captures must satisfy this policy."""
    policy = record.get('description_capture_policy')
    omission = record.get('description_omission')
    if policy is None:
        if omission is not None:
            errors.append(f'{where}: description omission requires its capture policy')
        return
    if policy != DESCRIPTION_POLICY:
        errors.append(f'{where}: unknown description capture policy')
        return
    en, zh = record.get('description_en'), record.get('description_zh')
    if not isinstance(en, str) or not isinstance(zh, str) or en != zh or len(en) > MAX_DESCRIPTION_CHARACTERS:
        errors.append(f'{where}: bounded source descriptions must match and stay within the capture limit')
    if omission is None:
        return
    expected = {'reason', 'original_characters', 'original_utf8_bytes', 'original_sha256', 'limit_characters'}
    if not isinstance(omission, dict) or set(omission) != expected:
        errors.append(f'{where}: invalid description omission evidence')
        return
    characters, size = omission['original_characters'], omission['original_utf8_bytes']
    if (en != '' or zh != '' or omission['reason'] != OMISSION_REASON
            or omission['limit_characters'] != MAX_DESCRIPTION_CHARACTERS
            or type(characters) is not int or characters <= MAX_DESCRIPTION_CHARACTERS
            or type(size) is not int or size < characters or size > 4 * characters
            or not isinstance(omission['original_sha256'], str)
            or not re.fullmatch(r'[a-f0-9]{64}', omission['original_sha256'])):
        errors.append(f'{where}: oversized descriptions require empty text and valid fingerprint evidence')


def description_fallback(record, language):
    if record.get('description_omission'):
        return ('上游简介超过合集长度限制，未展示原文。' if language == 'zh'
                else 'Upstream description omitted because it exceeds the collection’s length limit.')
    return ('上游仓库未提供项目简介。' if language == 'zh'
            else 'No description supplied by the upstream repository.')
