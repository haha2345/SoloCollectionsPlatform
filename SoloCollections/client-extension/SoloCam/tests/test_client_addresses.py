import os
import struct
import unittest
from pathlib import Path

import pefile


WOW_EXE = Path(os.environ.get("SOLOCOLLECTIONS_WOW_EXE", ""))
IMAGE_BASE = 0x00400000


@unittest.skipUnless(
    os.environ.get("SOLOCOLLECTIONS_WOW_EXE") and WOW_EXE.is_file(),
    "set SOLOCOLLECTIONS_WOW_EXE to the supported local Wow.exe",
)
class ClientAddressTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.image = WOW_EXE.read_bytes()
        cls.pe = pefile.PE(data=cls.image)

    def bytes_at_va(self, virtual_address, length):
        offset = self.pe.get_offset_from_rva(virtual_address - IMAGE_BASE)
        return self.image[offset : offset + length]

    def relative_call_target(self, call_address):
        instruction = self.bytes_at_va(call_address, 5)
        self.assertEqual(0xE8, instruction[0])
        displacement = struct.unpack("<i", instruction[1:])[0]
        return call_address + 5 + displacement

    def test_set_camera_lua_method_calls_the_hooked_native_function(self):
        self.assertEqual(
            bytes.fromhex("55 8B EC 56 8B F1"),
            self.bytes_at_va(0x0095F9F0, 6),
        )
        self.assertEqual(0x0095F9F0, self.relative_call_target(0x009609D6))

    def test_render_hook_and_camera_coordinate_calls_match(self):
        self.assertEqual(
            bytes.fromhex("55 8B EC 81 EC C8 00 00 00"),
            self.bytes_at_va(0x0095FC30, 9),
        )
        self.assertEqual(0x004C1290, self.relative_call_target(0x0095FD82))
        self.assertEqual(0x004C1290, self.relative_call_target(0x0095FD8E))
        self.assertEqual(
            bytes.fromhex("8B BE A4 02 00 00"),
            self.bytes_at_va(0x0095FD5A, 6),
        )

    def test_data_mgr_set_coord_entry_is_the_expected_function(self):
        self.assertEqual(
            bytes.fromhex("55 8B EC 83 EC 18 D9 EE"),
            self.bytes_at_va(0x004C12B0, 8),
        )

    def test_native_m2_roll_uses_scalar_property_accessors(self):
        self.assertEqual(
            bytes.fromhex("55 8B EC 51 D9 EE 8B 4D 0C 8B 45 08 D9 5D FC 57"),
            self.bytes_at_va(0x004C11F0, 16),
        )
        self.assertEqual(
            bytes.fromhex("55 8B EC 8B 45 08 33 D2 3B C2 74 21 8B 4D 0C 3B"),
            self.bytes_at_va(0x004C1360, 16),
        )
        # The stock M2 camera loader assigns scalar slot 5 after vectors 7/8.
        self.assertEqual(0x004C1360, self.relative_call_target(0x00828CA2))

    def test_player_model_set_creature_and_direct_display_entries_match(self):
        self.assertEqual(
            bytes.fromhex("55 8B EC A1 D4 E4 C0 00"),
            self.bytes_at_va(0x00597960, 8),
        )
        self.assertEqual(
            bytes.fromhex("55 8B EC 8B 45 08 33 D2 39 91 E0 00 00 00"),
            self.bytes_at_va(0x00597840, 14),
        )
        self.assertEqual(0x004A81B0, self.relative_call_target(0x0059798A))
        self.assertEqual(0x0084DF20, self.relative_call_target(0x00597994))
        self.assertEqual(0x0084E070, self.relative_call_target(0x005979BA))
        self.assertEqual(0x00597700, self.relative_call_target(0x005979FB))


if __name__ == "__main__":
    unittest.main()
