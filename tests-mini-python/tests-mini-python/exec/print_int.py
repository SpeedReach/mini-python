print(42)

import random   
def test():
    a = 3
    if random.random() < 0.5:
        a = 4
        b = 0
    print(a)
    print(b)
test()