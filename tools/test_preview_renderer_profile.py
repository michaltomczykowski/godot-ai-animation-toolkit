import unittest
from preview_renderer_profile import LINUX, WINDOWS, validate_environment, validate_renderer_identity

class RendererProfileTests(unittest.TestCase):
    def test_linux_contract_unchanged(self):
        validate_environment(LINUX,'linux',':99')
        line='OpenGL API 4.5 (Core Profile) Mesa 24.2 - Compatibility - Using Device: Mesa - llvmpipe (LLVM 19)'
        self.assertEqual(validate_renderer_identity(LINUX,'linux',line),[line])
        with self.assertRaises(ValueError):validate_environment(LINUX,'linux',None)
        with self.assertRaises(ValueError):validate_renderer_identity(LINUX,'linux','OpenGL API 4.6 - Compatibility - Using Device: Vendor - Real GPU')
    def test_windows_explicit_host_and_context(self):
        self.assertEqual(validate_environment(WINDOWS,'win32',None),'windows')
        with self.assertRaises(ValueError):validate_environment(WINDOWS,'linux',':99')
        with self.assertRaises(ValueError):validate_environment(LINUX,'win32',None)
        with self.assertRaises(ValueError):validate_renderer_identity(WINDOWS,'linux','OpenGL API 4.6 - Compatibility - Using Device: Vendor - Device')
    def test_native_identity_not_vendor_allowlisted(self):
        for vendor,device in [('NVIDIA','GeForce RTX 4090'),('Intel','Intel Arc A770'),('AMD','Radeon RX 7900'),('Future Vendor','Future Device 1')]:
            line=f'OpenGL API 4.6 Driver 123 - Compatibility - Using Device: {vendor} - {device}'
            self.assertEqual(validate_renderer_identity(WINDOWS,'windows',line),[line])
    def test_known_software_and_translation_aliases_refused(self):
        for alias in ['llvmpipe','softpipe','swrast','SwiftShader','Microsoft Basic Render Driver','GDI Generic','WARP','lavapipe','ANGLE','Software Rasterizer']:
            line=f'OpenGL API 4.6 - Compatibility - Using Device: Vendor - {alias}'
            with self.subTest(alias=alias),self.assertRaises(ValueError):validate_renderer_identity(WINDOWS,'windows',line)
    def test_missing_identity_components_and_forged_claims_fail(self):
        for line in ['renderer: NVIDIA','OpenGL API','OpenGL API 4.6 - Compatibility - Using Device: NVIDIA','OpenGL API 4.6 - Compatibility - Using Device: NVIDIA - unknown','OpenGL API 4.6 - Forward+ - Using Device: Vendor - Device']:
            with self.subTest(line=line),self.assertRaises(ValueError):validate_renderer_identity(WINDOWS,'windows',line)
    def test_conflicting_identity_and_ansi(self):
        line='OpenGL API 4.6 - Compatibility - Using Device: Vendor - Real Device'
        self.assertEqual(validate_renderer_identity(WINDOWS,'windows','\x1b[32m'+line+'\x1b[0m'),[line])
        with self.assertRaises(ValueError):validate_renderer_identity(WINDOWS,'windows',line+'\nOpenGL API 4.6 - Compatibility - Using Device: Mesa - llvmpipe')

if __name__=='__main__':unittest.main()
