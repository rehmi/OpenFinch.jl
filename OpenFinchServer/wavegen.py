import collections

class BusVector:
    def __init__(self, changes):
        self.changes = changes
        
    def __getitem__(self, index):
        return self.changes[index]

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

    def __str__(self):
        return '\n'.join([f"Time:  {time:5d}, Mask: {mask:032b}" for time, mask in self.generate()])

    def __len__(self):
        return len(self.changes)

class WaveVector:
    def __init__(self, changes):
        self.changes = sorted(changes, key=lambda x: x[2])

    def generate(self):
        wave_vector = []
        prev_time = 0
        prev_mask = 0

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
                wave_vector.append((set_mask & ~prev_mask, clr_mask & prev_mask, delay))

            # Update previous mask and time
            prev_mask ^= (set_mask | clr_mask)
            prev_time = current_time

        return wave_vector

    def __str__(self):
        return '\n'.join([f"Delay: {delay:5d},  Set: {set_mask:032b}, Clear: {clr_mask:032b}" for set_mask, clr_mask, delay in self.generate()])

class WaveGen:
    def __init__(self):
        self.changes = collections.deque()

    def change_bit(self, bit_index, bit_value, time):
        self.changes.append((bit_index, bit_value, time))

    def sort_changes(self):
        self.changes = collections.deque(sorted(self.changes, key=lambda x: x[2]))


def test_wavegen():
    wavegen = WaveGen()

    # Make some changes to the bit vector
    wavegen.change_bit(0, 1, 10)
    wavegen.change_bit(1, 0, 20)
    wavegen.change_bit(2, 1, 30)
    wavegen.change_bit(3, 0, 40)

    # Generate the bus vector
    bus_vector = BusVector(wavegen.changes)
    print("Bus Vector after first set of changes:")
    print(bus_vector)

    # Make some out-of-order changes to the bit vector
    wavegen.change_bit(1, 1, 5)
    wavegen.change_bit(3, 1, 35)

    # Generate the bus vector again
    bus_vector = BusVector(wavegen.changes)
    print("\nBus Vector after out-of-order changes:")
    print(bus_vector)

    # Generate the wave vector
    wave_vector = WaveVector(wavegen.changes)
    print("\nWave Vector:")
    print(wave_vector)
    
    return wavegen

if __name__ == '__main__':
    wg = test_wavegen()
