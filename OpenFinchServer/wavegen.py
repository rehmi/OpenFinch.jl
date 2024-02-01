import collections

class BusVector:
    def __init__(self, changes):
        self.changes = changes
        
    def __getitem__(self, index):
        return self.changes[index]

    def __str__(self):
        return '\n'.join([f"Time:  {time:5d}, Mask: {mask:032b}" for time, mask in self.generate()])

    def __len__(self):
        return len(self.changes)
    
    def generate(self):
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

    def __str__(self):
        return '\n'.join([f"Delay: {delay:5d},  Set: {set_mask:032b}, Clear: {clr_mask:032b}" for set_mask, clr_mask, delay in self.generate()])

    def generate(self):
        wave_vector = []
        prev_time = 0

        for bit_index, bit_value, current_time in self.changes:
            # Calculate masks for set and clear operations
            set_mask = 0
            clr_mask = 0

            # Calculate delay since last change
            delay = current_time - prev_time

            # If delay < 0, the changes are not properly sorted.
            if delay < 0:
                raise ValueError("Time of change is less than current time")

            # Update masks based on the bit value
            if bit_value:
                set_mask |= (1 << bit_index)
            else:
                clr_mask |= (1 << bit_index)

            # Add the transition to the wave vector if there was a change
            if set_mask or clr_mask:
                wave_vector.append((set_mask, clr_mask, delay))

            # Update previous mask and time
            prev_time = current_time

        return wave_vector


class WaveGen:
    def __init__(self):
        self._changes = []

    def change_bit(self, bit_index: int, bit_value: int, time: int) -> None:
        """Add a change to the bit vector, maintaining sorted order."""
        self._changes.append((bit_index, bit_value, time))
        self._changes.sort(key=lambda x: x[2])

    @property
    def changes(self):
        """Get the list of changes."""
        return self._changes.copy()


import unittest

class TestWaveGen(unittest.TestCase):
    def test_changes_ordered(self):
        wavegen = WaveGen()

        wavegen.change_bit(0, 1, 10)
        wavegen.change_bit(1, 0, 20)
        wavegen.change_bit(2, 1, 30)
        wavegen.change_bit(3, 0, 40)

        self.assertEqual(wavegen.changes, [(0, 1, 10), (1, 0, 20), (2, 1, 30), (3, 0, 40)])

    def test_bus_vector_generation(self):
        wavegen = WaveGen()

        wavegen.change_bit(0, 1, 10)
        bus_vector = BusVector(wavegen.changes)

        expected_result = [(0, 0b0), (10, 0b1)]
        self.assertEqual(bus_vector.generate(), expected_result)

    def test_out_of_order_changes_handled(self):
        wavegen = WaveGen()

        wavegen.change_bit(3, 1, 35)
        wavegen.change_bit(0, 1, 10)
        wavegen.change_bit(3, 0, 40)
        wavegen.change_bit(1, 1, 5)
        wavegen.change_bit(2, 1, 30)
        wavegen.change_bit(1, 0, 20)

        self.assertEqual(wavegen.changes, [(1, 1, 5), (0, 1, 10), (1, 0, 20), (2, 1, 30), (3, 1, 35), (3, 0, 40)])

    def test_wave_vector_generation(self):
        wavegen = WaveGen()

        wavegen.change_bit(1, 1, 5)
        wavegen.change_bit(0, 1, 10)
        wavegen.change_bit(1, 0, 20)
        wavegen.change_bit(2, 1, 30)
        wavegen.change_bit(3, 1, 35)
        wavegen.change_bit(3, 0, 40)

        wave_vector = WaveVector(wavegen.changes)
        
        # Compare the delays and the set_mask, clr_mask
        expected_result = [
            (0, 0, 5),         # Initial state (added to properly reflect no change initially)
            (0b10, 0, 5),      # From (1, 1, 5) (change in bit 1)
            (0b1, 0, 10),       # From (0, 1, 10) (change in bit 0)
            (0, 0b10, 10),     # From (1, 0, 20) (change in bit 1)
            (0b100, 0, 5),    # From (2, 1, 30) (change in bit 2)
            (0b1000, 0, 5),    # From (3, 1, 35) (change in bit 3)
            (0, 0b1000, 0),    # From (3, 0, 40) (change in bit 3)
        ]
        generated_result = [(set_mask, clr_mask, delay) for set_mask, clr_mask, delay in wave_vector.generate()]
        self.assertEqual(generated_result, expected_result)
        

# Run the tests when the script is executed
if __name__ == '__main__':
    # wg = test_wavegen()
    unittest.main()
