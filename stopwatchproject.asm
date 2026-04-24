;
; HelloLCD.asm
;
; Created: 4/20/2026 8:11:02 AM
; Author : pallen
;

.equ TICK_DELAY =  (1000000 / ((1 / 16.0) * 1024.0 )) - 1

.equ BTN_DIR  = DDRD
.equ BTN_MODE = PORTD
.equ BTN_READ = PD2

.def tickFlag = r21
.def readFlag = r22

; ------------------------------------------------------------
; Vector Table
; ------------------------------------------------------------
.org 0x0000                   ; Reset Vector
          jmp       main

.org INT0addr                 ; External Interrupt Request 0
          jmp       read_ISR

.org OC1Aaddr                 ; Timer/Counter1 Compare Match A
          jmp       tick_ISR

.org INT_VECTORS_SIZE         ; End of vector table


;--------------------------------------------------------
; Strings and lookup-tables
;--------------------------------------------------------
message: .db "Hello: " ,0

;--------------------------------------------------------
; Inculdes
;--------------------------------------------------------
.include "lcd.inc"

.include "util.inc"

;--------------------------------------------------------
main:
;--------------------------------------------------------
          ; initialize stack
          ldi       r16, high(RAMEND)
          out       SPH, r16
          ldi       r16, low(RAMEND)
          out       SPL, r16

          rcall     gpio_init           ; button

          rcall     LCD_INIT            ; LCD screen

          rcall     RAND_INIT           ; random number generator

          rcall     timer_init          ; initi

          clr       tickFlag            ; tickFlag = false
          clr       readFlag            ; readFlag = false

          sei                           ; enable global interrupts          
main_loop:

          tst       tickFlag            ; wait for next tick
          breq      end_main

          tst       readFlag            ; wait for user to press read button
          breq      end_read

          ; reset LCD screen
          rcall     LCD_CLEAR
          rcall     LCD_HOME

          ; init Z pointer to message and write it
          ldi       ZH, high(message << 1)
          ldi       ZL, low(message << 1)
          rcall     LCD_WRITE_STRING_PM

          ; min = 100
          ldi       r26, low(100)
          ldi       r27, high(100)

          ; max = 300
          ldi       r28, low(300)
          ldi       r29, high(300)

          rcall     RAND_BETWEEN

          mov       r31, r27
          mov       r30, r26
          rcall     LCD_PRINT_UINT16

          clr       readFlag            ; readFlag = false
end_read:

          clr       tickFlag            ; tickFlag = false

end_main:
          rjmp      main_loop


; ------------------------------------------------------------
gpio_init:
; ------------------------------------------------------------
          ; initialize buttons
          cbi       BTN_DIR, BTN_READ   ; input mode
          sbi       BTN_MODE, BTN_READ  ; pull-up
          sbi       EIMSK, INT0         ; enable INT0
          ldi       r20, (0b10 << ISC10); fall-edge trigger
          sts       EICRA, r20          ; set sense bits

          ret


; ------------------------------------------------------------
timer_init:
; ------------------------------------------------------------
          ; Load TCNT1H:TCNT1L with initial count
          clr       r20
          sts       TCNT1H, r20
          sts       TCNT1L, r20

          ; Load OCR1AH:OCR1AL with stop count
          lds       r20, high(TICK_DELAY)
          sts       OCR1AH, r20
          lds       r20, low(TICK_DELAY)
          sts       OCR1AL, r20

          ; Load TCCR1A & TCCR1B
          clr       r20                 ; CTC mode
          sts       TCCR1A, r20

          ; Clock Prescaler   setting the clock starts the timer
          ldi       r20, (0b01 << WGM12); CTC mode
          ori       r20, (0b101 << CS10); clk/1024
          sts       TCCR1B, r20

          ; enable interrupts
          ldi       r20, (1 << OCIE1A)
          sts       TIMSK1, r20
          ret


; ------------------------------------------------------------
read_ISR:
; ------------------------------------------------------------
          ldi       readFlag, 1         ; readFlag = true
          
          reti

; ------------------------------------------------------------
tick_ISR:
; ------------------------------------------------------------
          push      r20

          ldi       tickFlag, 1         ; tickFlag = true

          ; Load TCNT1H:TCNT1L with initial count
          clr       r20
          sts       TCNT1H, r20
          sts       TCNT1L, r20

          pop       r20
          reti
