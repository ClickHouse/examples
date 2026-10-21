"""Managed executable pins checked before measurement; reference evidence stays unchanged."""
ENGINE_VERSION = '26.8.33.8'
ENGINE_PINS = {
    # Retained for validation of the committed reference and earlier local runs.
    '26.8.32.16': {
        'aarch64': '0d0719833575d7f930580bba7769069d4bc054a8af037e8b8bc3955f7368f937',
    },
    # Installed with clickhousectl 0.4.2 and hashed before any measurements.
    '26.8.33.8': {
        'aarch64': '37064a16e44f3288d981a7f2125f3bae9d4579aec7f2bcf397673363f08ee327',
        'x86_64': '1d008a3870f8bc45cd95df4e3e3beee5bad2a0a54e2a856fe3e34e1de0c6eb6b',
    },
}
BINARY_SHA256 = ENGINE_PINS[ENGINE_VERSION]
