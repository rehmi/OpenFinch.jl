class WaveGen:
    def __init__(self):
        self._changes = []

    def change_bit(self, bit_index: int, bit_value: int, time: float) -> None:
        """Add a change to the bit vector, maintaining sorted order."""
        self._changes.append((bit_index, bit_value, time))
        self._changes.sort(key=lambda x: x[2])

    @property
    def changes(self):
        """Get the list of changes."""
        return self._changes.copy()
    
    @property
    def wave_vector(self):
        return self.WaveVector(self.changes)

    @property
    def bus_vector(self):
        return self.BusVector(self.changes)

    
    class BusVector:
        def __init__(self, changes):
            self.changes = changes
            self.bus_vector = self._generate()
            
        def __getitem__(self, index):
            return self.bus_vector[index]

        def __str__(self):
            return '\n'.join([f"Time:  {time:5d}, Mask: {mask:032b}" for time, mask in self.bus_vector])

        def __len__(self):
            return len(self.bus_vector)
        
        def _generate(self):
            changes = sorted(self.changes, key=lambda x: x[2])
            bus_vector = []
            current_time = 0
            current_mask = 0
            for bit_index, bit_value, time in changes:
                delay = time - current_time
                if delay < 0:
                    raise ValueError("Time of change is less than current time")
                else:
                    bus_vector.append((current_time, current_mask))
                current_time = time
                if bit_value:
                    current_mask |=  (1 << bit_index)
                else:
                    current_mask &= ~(1 << bit_index)
                    
            # Include the final state at the end of simulation, after processing all changes.
            bus_vector.append((current_time, current_mask))
                    
            return bus_vector


    class WaveVector:
        def __init__(self, changes):
            self.changes = sorted(changes, key=lambda x: x[2])
            self.wave_vector = self._generate()

        def __str__(self):
            return '\n'.join([f"Delay: {delay:5d},  Set: {set:032b}, Clear: {clr:032b}" for set, clr, delay in self.wave_vector])
        
        def __getitem__(self, index):
            return self.wave_vector[index]

        def __len__(self):
            return len(self.wave_vector)

        def _generate(self):
            wave_vector = []
            prev_time = 0
            set_mask = 0
            clr_mask = 0

            # Iterate over sorted changes
            for bit_index, bit_value, current_time in self.changes:
                # Calculate delay since last change
                delay = current_time - prev_time
                
                # If delay < 0, the changes are not properly sorted.
                if delay < 0:
                    raise ValueError("Time of change is less than current time")
                
                # If there was a delay, record it and reset the masks
                if delay > 0:
                    wave_vector.append((set_mask, clr_mask, delay))
                    set_mask = 0
                    clr_mask = 0

                # Update masks based on the bit value
                if bit_value:
                    set_mask |= (1 << bit_index)
                else:
                    clr_mask |= (1 << bit_index)

                # Update previous time
                prev_time = current_time

            # Include the final change if any mask is set
            if set_mask or clr_mask:
                wave_vector.append((set_mask, clr_mask, 0))

            return wave_vector


import unittest

class TestWaveGen(unittest.TestCase):
    def test_changes_ordered(self):
        wavegen = WaveGen()
        wavegen.change_bit(0, 1, 10)
        wavegen.change_bit(1, 0, 20)
        wavegen.change_bit(2, 1, 30)
        wavegen.change_bit(3, 0, 40)
        expected_result = [(0, 1, 10), (1, 0, 20), (2, 1, 30), (3, 0, 40)]
        self.assertEqual(wavegen.changes, expected_result)

    def test_out_of_order_changes_handled(self):
        wavegen = WaveGen()
        wavegen.change_bit(3, 1, 35)
        wavegen.change_bit(0, 1, 10)
        wavegen.change_bit(3, 0, 40)
        wavegen.change_bit(1, 1, 5)
        wavegen.change_bit(2, 1, 30)
        wavegen.change_bit(1, 0, 20)
        expected_result = [(1, 1, 5), (0, 1, 10), (1, 0, 20), (2, 1, 30), (3, 1, 35), (3, 0, 40)]
        self.assertEqual(wavegen.changes, expected_result)

    def test_bus_vector_generation(self):
        wavegen = WaveGen()
        wavegen.change_bit(0, 1, 10)
        expected_result = [(0, 0b0), (10, 0b1)]
        self.assertEqual(wavegen.bus_vector[:], expected_result)

    def test_wave_vector_generation(self):
        wavegen = WaveGen()
        wavegen.change_bit(1, 0, 20)
        wavegen.change_bit(0, 1, 10)
        wavegen.change_bit(3, 0, 40)
        wavegen.change_bit(3, 1, 35)
        wavegen.change_bit(1, 1, 5)
        wavegen.change_bit(2, 1, 30)
        # Compare the delays and the set_mask, clr_mask
        expected_result = [
            (0b0000, 0b0000,  5),  # Initial delay
            (0b0010, 0b0000,  5),  # (1, 1,  5)
            (0b0001, 0b0000, 10),  # (0, 1, 10)
            (0b0000, 0b0010, 10),  # (1, 0, 20)
            (0b0100, 0b0000,  5),  # (2, 1, 30)
            (0b1000, 0b0000,  5),  # (3, 1, 35)
            (0b0000, 0b1000,  0),  # (3, 0, 40)
        ]
        self.assertEqual(wavegen.wave_vector[:], expected_result)
        

# Run the tests when the script is executed
if __name__ == '__main__':
    # wg = test_wavegen()
    unittest.main()
