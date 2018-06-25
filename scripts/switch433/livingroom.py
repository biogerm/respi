import time
import sys
import RPi.GPIO as GPIO

b = '110110000110011000011101'
c = '110110000110011000001100'
a       = '0101001100101101010010110010101101010100101010'
all_off = '0101001100101101010010110010101101001011010010'
onehigh_delay  = 0.000073
zerolow_delay  = 0.00011
endhigh_delay  = 0.00038


NUM_ATTEMPTS = 60
TRANSMIT_PIN = 23

def transmit_code(code):
    '''Transmit a chosen code string using the GPIO transmitter'''
    GPIO.setmode(GPIO.BCM)
    GPIO.setup(TRANSMIT_PIN, GPIO.OUT)
    for t in range(NUM_ATTEMPTS):
        for i in code:
            if i == '1':
                GPIO.output(TRANSMIT_PIN, 1)
                time.sleep(onehigh_delay)
            elif i == '0':
                GPIO.output(TRANSMIT_PIN, 0)
                time.sleep(zerolow_delay)
            else:
                continue
        GPIO.output(TRANSMIT_PIN, 1)
        time.sleep(endhigh_delay)
    GPIO.cleanup()

if __name__ == '__main__':
    for argument in sys.argv[1:]:
        exec('transmit_code(' + str(argument) + ')')
