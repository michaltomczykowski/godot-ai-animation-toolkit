import math
from pathlib import Path
import struct
import tempfile
import unittest
import wave

from check_saved_audio import check


class AudioOutput(unittest.TestCase):
    def test_complete_pcm_and_negative_controls(self):
        rate = 8000
        with tempfile.TemporaryDirectory() as folder:
            source = Path(folder)/'input.wav'
            output = Path(folder)/'capture.wav'
            def write(path, data):
                with wave.open(str(path), 'wb') as stream:
                    stream.setparams((1, 2, rate, len(data), 'NONE', 'not compressed'))
                    stream.writeframes(struct.pack('<'+'h'*len(data), *data))
            tone = [round(9000*math.sin(2*math.pi*440*i/rate)) for i in range(round(.3*rate))]
            write(source, tone)
            for variant in ('valid', 'silent', 'missing_reset', 'wrong_pitch', 'late', 'truncated'):
                data = [0] * (12*rate)
                for take in range(2 if variant != 'missing_reset' else 1):
                    start = round((take*6 + (.2 if variant == 'late' else .02))*rate)
                    cue = tone if variant != 'wrong_pitch' else [round(9000*math.sin(2*math.pi*550*i/rate)) for i in range(len(tone))]
                    if variant != 'silent': data[start:start+len(cue)] = cue
                if variant == 'truncated': data = data[:7*rate]
                write(output, data)
                self.assertEqual(check(source, output)['audio_output_pass'], variant == 'valid', variant)


if __name__ == '__main__':
    unittest.main()
