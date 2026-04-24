
;--------------------------------------------------------
RAND_INIT:
; initialize random generator
; Uses:
;   R16
;--------------------------------------------------------
push      r16

; A0 / PC0 as analog input, no pull-up
cbi       DDRC, 0
cbi       PORTC, 0

; ADMUX:
; REFS0 = 1  -> AVcc reference
; MUX[3:0]=0 -> ADC0
ldi       r16, (1<<REFS0)
sts       ADMUX, r16

; ADCSRA:
; ADEN = 1           enable ADC
; ADPS2:0 = 111      prescaler 128
ldi       r16, (1<<ADEN) | (1<<ADPS2) | (1<<ADPS1) | (1<<ADPS0)
sts       ADCSRA, r16

pop       r16
ret

;--------------------------------------------------------
ADC_READ  :
; read ADC port pin
; Uses:
;   R16,
; Returns:
;   R25:R24 - 10-bit result 0-1023
;--------------------------------------------------------
push      r16

; start conversion
lds       r16, ADCSRA
ori       r16, (1<<ADSC)
sts       ADCSRA, r16

; wait for ADSC to clear
adc_wait:
lds       r16, ADCSRA
sbrc      r16, ADSC
rjmp      adc_wait

; read result: ADCL first, then ADCH
lds       r24, ADCL
lds       r25, ADCH
; now r25:r24 = 10-bit result 0..1023

pop       r16
ret


;--------------------------------------------------------
RAND_BETWEEN:
; Generate random integer in inclusive range [min, max]
;
; Parameters:
;   R27:R26 = min
;   R29:R28 = max
;
; Returns:
;   R27:R26 = random value in [min, max]
;
; Calls:
;   ADC_READ   ; returns 10-bit ADC value in R25:R24
;
; Uses:
;   R18, R19, R20, R21, R22, R23, R24, R25
;
; Notes:
;   Assumes min <= max
;   Range is inclusive
;--------------------------------------------------------
          push      r18
          push      r19
          push      r20
          push      r21
          push      r22
          push      r23

;--------------------------------------------------------
; Compute range = max - min + 1
;   range -> R23:R22
;--------------------------------------------------------
          movw      r22, r28        ; R23:R22 = max
          sub       r22, r26        ; max - min
          sbc       r23, r27
          inc       r22             ; +1 for inclusive range
          brne      range_done
          inc       r23
range_done:

;--------------------------------------------------------
; Build 10-bit random value in R19:R18
;--------------------------------------------------------
          clr       r18             ; random low
          clr       r19             ; random high
          ldi       r21, 10

rand_loop:
; small delay between samples
          ldi       r20, 80
rand_delay:
          dec       r20
          brne      rand_delay

          rcall     ADC_READ        ; ADC result in R25:R24

; derive 1 bit from low ADC bits
          mov       r20, r24
          lsr       r20
          eor       r20, r24
          andi      r20, 1

; shift accumulator left by 1 and insert new bit
          lsl       r18
          rol       r19
          or        r18, r20

          dec       r21
          brne      rand_loop

; Move random value to R25:R24 for reduction
          movw      r24, r18

;--------------------------------------------------------
; Reduce random value modulo range
;   value  = R25:R24
;   range  = R23:R22
;--------------------------------------------------------
mod_loop:
          cp        r24, r22
          cpc       r25, r23
          brlo      mod_done

          sub       r24, r22
          sbc       r25, r23
          rjmp      mod_loop

mod_done:
;--------------------------------------------------------
; Add min back in
;--------------------------------------------------------
          add       r24, r26
          adc       r25, r27

; Return in R27:R26
          movw      r26, r24

          pop       r23
          pop       r22
          pop       r21
          pop       r20
          pop       r19
          pop       r18
          ret