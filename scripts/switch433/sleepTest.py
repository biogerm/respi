from datetime import datetime
import time

def check_sleep(amount):
    start = datetime.now()
    time.sleep(amount)
    end = datetime.now()
    delta = end - start
    return delta.seconds + delta.microseconds/1000000.0

error = 0
for i in range(100):
    error += abs(check_sleep(0.050) - 0.050)
error /= 100
print error

