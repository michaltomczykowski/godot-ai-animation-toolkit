"""Explicit rendered-preview host and logged renderer profiles (no GPU probes)."""
import re

LINUX = 'linux-mesa-llvmpipe'
WINDOWS = 'windows-native-opengl'
PROFILES = (LINUX, WINDOWS)
ANSI = re.compile(r'\x1b\[[0-9;]*m')
SOFTWARE = re.compile(r'llvmpipe|softpipe|swrast|swiftshader|software(?:\s+rasterizer|\s+renderer|\s+adapter)?|microsoft\s+(?:basic|gdi)|gdi\s+generic|warp|lavapipe|angle', re.I)


def platform_name(value):
    value=str(value).lower()
    if value in ('windows','win32','cygwin'):return 'windows'
    if value in ('linux','linux2'):return 'linux'
    raise ValueError('unsupported rendered-preview host/context platform: '+value)


def validate_environment(profile, host_platform, display):
    if profile not in PROFILES:raise ValueError('unknown renderer profile')
    host=platform_name(host_platform)
    expected='linux' if profile==LINUX else 'windows'
    if host!=expected:raise ValueError('renderer profile/host platform mismatch')
    if profile==LINUX and not display:raise ValueError('DISPLAY is required; use xvfb-run')
    return host


def validate_renderer_identity(profile, context_platform, text):
    if profile not in PROFILES:raise ValueError('unknown renderer profile')
    platform=platform_name(context_platform)
    if platform!=('linux' if profile==LINUX else 'windows'):
        raise ValueError('renderer profile/context platform mismatch')
    clean=ANSI.sub('',text)
    identity=[line for line in clean.splitlines() if 'OpenGL API' in line]
    if not identity:raise ValueError('editor log has no actual OpenGL API identity')
    if profile==LINUX:
        # Preserve the existing Linux llvmpipe condition, without relaxing it.
        if not any('llvmpipe' in line.lower() for line in identity):
            raise ValueError('editor log does not identify actual Mesa llvmpipe OpenGL renderer')
    else:
        # Read the engine's actual API/version, vendor and device. No vendor allowlist:
        # hardware vendors can add drivers. Known software/translation aliases fail.
        if any(SOFTWARE.search(line) for line in identity):
            raise ValueError('Windows native OpenGL profile refuses software/translation renderer')
        for line in identity:
            match=re.search(r'OpenGL API\s+(\d+\.\d+[^\r\n]*?)\s+-\s+Compatibility\s+-\s+Using Device:\s*(.+?)\s+-\s*(.+?)\s*$',line)
            if not match or not all(part.strip() for part in match.groups()):
                raise ValueError('Windows OpenGL identity lacks API/driver, vendor or device')
            if any(part.strip().lower() in ('unknown','none','null','n/a') for part in match.groups()):
                raise ValueError('Windows OpenGL identity contains unknown driver/device')
    return identity
