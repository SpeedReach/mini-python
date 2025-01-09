def filter_out(p, l):
    i = 0
    for x in l:
        a = x > p
        b = x % p == 0
        if a and b:
            print(i)
            l[i] = 0

        i = i + 1

def main():
    l = list(range(10))
    filter_out(2, l)
main()