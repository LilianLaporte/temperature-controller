 
;=====================MACROS============================
 .macro	MOTOR 
	P0	PORTE,SERVO1	;low
	WAIT_US 20000
	P1	PORTE,SERVO1		
loop:
	SUBI2	@0,@1,0x1
	brne	loop
	P0	PORTE,SERVO1	;high
	.endmacro

.macro	AFFICHER
	rcall	lcd_home

	mov a0,@0
	PRINTF	LCD
	.db	"T=",FDEC,a,"C ",CR,0  ;display temperature

	mov a0, @1
	mov b0, @2
	PRINTF	LCD
	.db	LF,"Tmin=",FDEC,b," Tmax=",FDEC,a,"   ",0  ;display Tmin & Tmax
	.endmacro


.include "definitions.asm"
.include "macros.asm"

.org	0
	rjmp	reset
.org INT0addr			;Button 0
	jmp ext_int0
.org INT1addr			;Button 1
	jmp ext_int1
.org INT2addr			;Button 2
	jmp ext_int2
.org INT3addr			;Button 3
	jmp ext_int3
.org	OVF0addr		; timer overflow 0 interrupt vector
	rjmp	overflow0
.org	0x30

; =============== interrupt service routines ================

ext_int0:					;Button 0
	in	_sreg,SREG

	ldi a0, 0b00000010
	mov a1, d1
	sub a1, a0			;Tmax-2

	mov a0, c3

	sub a1, a0			;Tmax-1-Tmin
	brsh infcorrect		;Tmin<Tmax-1?

	out	SREG,_sreg
	reti
infcorrect:
	inc c3
	out	SREG,_sreg
	reti


ext_int1:					;Button 1
	in	_sreg,SREG
	
	ldi a0, 0b00000001
	mov a1, c3
	sub a1, a0
	ldi a0, 0b11111111
	sub a1, a0

	breq end2			;Tmin>0?
	dec c3
	
	out	SREG,_sreg
	reti
end2:
	out	SREG,_sreg
	reti


ext_int2:					;Button 2
	in	_sreg,SREG

	ldi a0, 0b00000001
	add a0, d1

	breq end1			;Tmax<255?
	inc d1

	out	SREG,_sreg
	reti
end1: 
	out	SREG,_sreg
	reti


ext_int3:					;Button 3
	in	_sreg,SREG
	dec d1

	ldi a0, 0b00000001
	add a0, c3
	
	sub a0, d1
	brsh correctsup			;Tmin<Tmax-1?

	out	SREG,_sreg
	reti
correctsup:
	mov d1, c3
	ldi a0, 0b00000001
	add d1, a0

	out	SREG,_sreg
	reti

overflow0:
	in _sreg,SREG

	rcall	wire1_reset			; send a reset pulse
	CA	wire1_write, skipROM
	CA	wire1_write, readScratchpad	
	rcall	wire1_read			; read temperature LSB
	MOVB b3,3,a0,7
	MOVB b3,2,a0,6
	MOVB b3,1,a0,5
	MOVB b3,0,a0,4	
	clr a0
	rcall	wire1_read			; read temperature MSB
	MOVB b3,6,a0,2
	MOVB b3,5,a0,1
	MOVB b3,4,a0,0				;b3=Val entière de la température
	
	rcall	wire1_reset			; send a reset pulse
	CA	wire1_write, skipROM	; skip ROM identification
	CA	wire1_write, convertT	; initiate temp conversion
	out	SREG,_sreg
	reti
	
; ===================================== initialisation (reset) ================================
reset: 
	LDSP	RAMEND			; set up stack pointer (SP)
	rcall	wire1_init		; initialize 1-wire(R) interface

	OUTI	DDRE,0xff		; configure portE to output
	;sbi	DDRE,SPEAKER	; make pin SPEAKER an output

	rcall	LCD_init		; initialize the LCD

	ldi r16,0x00	;configure portD as input
	out DDRD,r16

	OUTI	EIMSK,0b11001111
	OUTEI	EICRA,0b11111111	
	OUTI	TIMSK,(1<<TOIE0)
	OUTI	ASSR, (1<<AS0)	; clock from TOSC1 (external)
	OUTI	TCCR0,5			; CS0=1 CK/256

	ldi a2, 40 
	mov d1,a2	; Tmax
	ldi a2,25
	mov b3,a2	; Tact
	ldi a2,2
	mov c3,a2	; Tmin

	rcall	wire1_reset			; send a reset pulse
	CA	wire1_write, skipROM	; skip ROM identification
	CA	wire1_write, convertT	; initiate temp conversion	

	sei							; set global interrupt
	rjmp main


.include "lcd.asm"			; include the LCD routines
.include "printf.asm"		; include formatted print routines
.include "wire1.asm"		; include Dallas 1-wire(R) routines
.include "math.asm"			; include math routines
.include "sound.asm"		; include sound routines

main:
	in _sreg,SREG
	cli
	mov a0,c3
	sub a0, b3 ; T<Tmin ?

	brpl t_min
	
	mov a0,d1
	sub a0, b3 ; T>Tmax ?

	brcs t_sup

	out SREG,_sreg
	sei 

	rcall conversion

	rjmp main

t_min:
	rcall tmin
	rjmp main

t_sup:
	rcall tsup
	rjmp main

; ====TMIN====
tmin:
	AFFICHER b3,d1,c3

	ldi b0, 0b11101000
	ldi b1, 0b00000011	;b=paramters for the motor
	MOTOR b1,b0			;Activate it when the motor is connected

	out SREG,_sreg
	sei
	rjmp main			

	ret

; ====TSUP====
tsup:
	AFFICHER b3,d1,c3

	ldi b0, 0b11010000
	ldi b1, 0b00000111	;b=paramters for the motor
	MOTOR b1,b0			;Activate it when the motor is connected
	;rcall alarm		;Activate it when the speaker is connected

	out SREG,_sreg
	sei	

	ret
	
;====CONVERSION====
conversion :
	in _sreg,SREG
	cli

	mov b0, b3 ; b0 = Tact
	mov a0, c3 ; a0 = Tmin

	sub b0, a0 ; b0 = Tact-Tmin

	clr c0
	clr c1
	
	ldi a0, 0b11101000
	ldi a1, 0b00000011
	
	rcall mul21	;c = 1000*(Tact-Tmin)

	mov a0, c0
	mov a1, c1
	
	mov b0, d1 ; b0 = Tmax
	mov b1, c3 ; b1 = Tmin

	sub b0, b1 ; b0 = Tmax - Tmin

	rcall div21 ; c = 1000*(Tact-Tmin)/(Tmax-Tmin)
	
	mov d2,c1
	mov b2,c0	

	AFFICHER b3,d1,c3
	
	mov b0,b2
	mov b1,d2	

	ADDI2	b1,b0,1000	; add an offset of 1000	
	MOTOR b1,b0			;Activate it when the motor is connected

	out SREG,_sreg
	sei

	ret

; ====ALARM====
alarm: 
	ldi a0,250	;parameter for the routine sound
	ldi b0,20	;parameter for the routine sound
	rcall sound
	ret
