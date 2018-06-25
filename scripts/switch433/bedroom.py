import time
import sys
import RPi.GPIO as GPIO

a = '110110000110011000101110'
b = '110110000110011000011101'
c = '1101110111100111110111110001'
d = 'I1O11101I11O011I11O11111OOO1'
all_off = '110110000110011011111011'
onehigh_delay = 0.00004
shortlow_delay = 0.00012
longlow_delay = 0.0003
zerohigh_delay = 0.00022

extended_delay = 0.00052
delay_low = 0.0001

NUM_ATTEMPTS = 20
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
                GPIO.output(TRANSMIT_PIN, 0)
                time.sleep(shortlow_delay)
            elif i == '0':
                GPIO.output(TRANSMIT_PIN, 1)
                time.sleep(zerohigh_delay)
                GPIO.output(TRANSMIT_PIN, 0)
                time.sleep(shortlow_delay)
            elif i == 'I':
		GPIO.output(TRANSMIT_PIN, 1)
                time.sleep(onehigh_delay)
                GPIO.output(TRANSMIT_PIN, 0)
                time.sleep(longlow_delay)
            elif i == 'O':
                GPIO.output(TRANSMIT_PIN, 1)
                time.sleep(zerohigh_delay)
                GPIO.output(TRANSMIT_PIN, 0)
                time.sleep(longlow_delay)
            else:
                continue
        GPIO.output(TRANSMIT_PIN, 1)
        time.sleep(extended_delay)
        GPIO.output(TRANSMIT_PIN, 0)
        time.sleep(delay_low)
    GPIO.cleanup()

if __name__ == '__main__':
    for argument in sys.argv[1:]:
        exec('transmit_code(' + str(argument) + ')')
