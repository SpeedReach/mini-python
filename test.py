def primes(n):
    l = range2(2, n)
    nb = 0
    for x in l:
        if x > 0:
            l[nb] = x
            nb = nb + 1
            filter_out(x, l)
    return prefix(nb, l)