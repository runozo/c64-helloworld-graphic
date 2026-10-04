; =====================================================================
;  graphic.asm  -  "HELLO, WORLD!" GRAFICO con SCROLLING per C64
; ---------------------------------------------------------------------
;  CPU      : MOS 6510
;  Assembler: ACME
;  Output   : graphic.prg
;
;  La scritta viene DISEGNATA come pixel in un bitmap hires 320x200 e
;  scorre orizzontalmente da destra verso sinistra (marquee continuo).
;
;  Modalita' video: standard bitmap (hires) del VIC-II
;    - bitmap      : $2000-$3FFF  (8000 byte, 1 bit = 1 pixel)
;    - video matrix: $0400-$07E7  (colore per ogni cella 8x8)
;    - $D018 = $18  -> matrix $0400, bitmap $2000
;    - $D011 = $3B  -> BMM=1 (bitmap), DEN=1, yscroll=3, 25 righe
;    - $D016 = $08  -> MCM=0 (hires), 40 colonne, xscroll=0
;
;  Layout del bitmap: le 8 righe di pixel di una cella 8x8 sono
;  contigue; la cella (riga R, col C) sta a  $2000 + R*320 + C*8.
;  Per lo scroll orizzontale NON si puo' trattare la riga come un array
;  lineare di 320 byte (i byte di una stessa riga di pixel distano 8):
;  si scorre una riga di pixel per volta (vedi shift_line).
;
;  Colori: il byte della video matrix seleziona i due colori di ogni
;  cella: nibble ALTO = pixel a 1, nibble BASSO = pixel a 0.
;  Usiamo $16 = bianco (1) su blu (6).
; =====================================================================

!cpu 6510
!to "graphic.prg", cbm

; ---------------------------------------------------------------------
;  Indirizzi hardware
; ---------------------------------------------------------------------
BITMAP     = $2000            ; base del bitmap hires
SCREEN     = $0400            ; video matrix (40x25)

VIC_BORDER = $d020
VIC_BG     = $d021
VIC_CTRL1  = $d011
VIC_CTRL2  = $d016
VIC_MEM    = $d018
VIC_RASTER = $d012

; ---------------------------------------------------------------------
;  Variabili in zero page (usiamo SEI, quindi la zero page e' libera)
; ---------------------------------------------------------------------
zp_src      = $fb             ; puntatore al glifo (sorgente)
zp_dst      = $fd             ; puntatore alla cella nel bitmap
msg_idx     = $f7             ; indice nella tabella del messaggio
frame_count = $f6             ; contatore frame per l'inserimento glifi

; ---------------------------------------------------------------------
;  Parametri dello scrolling
; ---------------------------------------------------------------------
TEXT_ROW   = 12               ; riga di caratteri (0..24)
CELLS      = 40               ; celle per riga
line       = BITMAP + TEXT_ROW*320

; ---------------------------------------------------------------------
;  BASIC stub: 10 SYS 2061 -> codice a $080D
; ---------------------------------------------------------------------
* = $0801
        !byte $0b, $08, $0a, $00, $9e
        !byte $32, $30, $36, $31
        !byte $00, $00, $00

; ---------------------------------------------------------------------
;  CODICE
; ---------------------------------------------------------------------
* = $080d
start:
        sei                   ; ferma IRQ: timing via raster, ZP libera
        lda #$06
        sta VIC_BORDER        ; bordo blu
        sta VIC_BG            ; sfondo blu

        jsr clear_bitmap      ; bitmap tutto a 0
        jsr fill_screen       ; video matrix a $16 = bianco su blu
        jsr fill_line         ; pre-riempe la riga col messaggio

        lda #$3b              ; abilita la modalita' bitmap
        sta VIC_CTRL1
        lda #$08              ; hires, 40 colonne
        sta VIC_CTRL2
        lda #$18              ; matrix $0400 + bitmap $2000
        sta VIC_MEM

        lda #$08
        sta frame_count

; ---------------------------------------------------------------------
;  Loop principale: 1 pixel di scroll per frame; ogni 8 pixel (1 cella)
;  entra un nuovo carattere dalla destra.
; ---------------------------------------------------------------------
scroll_loop:
        jsr wait_frame
        jsr shift_line
        dec frame_count
        bne scroll_loop
        lda #$08
        sta frame_count
        jsr insert_char
        jmp scroll_loop

; ---------------------------------------------------------------------
;  wait_frame: attende la linea raster 248 (una volta per frame)
; ---------------------------------------------------------------------
wait_frame:
        lda #$f8
wf_wait:
        cmp VIC_RASTER
        bne wf_wait
        rts

; ---------------------------------------------------------------------
;  shift_line: scorre a sinistra di 1 pixel i 320 byte della riga.
;  ROL propaga il bit7 di un byte nel bit0 del byte precedente, quindi
;  si processa dal byte piu' a destra (319) al piu' a sinistra (0).
; ---------------------------------------------------------------------
shift_line:
        ; Il bitmap e' interlacciato per celle: una cella 8x8 occupa 8
        ; byte CONTIGUI, quindi i byte di una stessa riga di pixel sono a
        ; distanza 8 (uno per cella). Uno scroll orizzontale va fatto
        ; riga di pixel per riga di pixel (p = 0..7), scorrendo le 40
        ; celle (c = 39..0) con ROL e catena di carry continua.
        ; Generiamo 320 ROL assoluti con "!for": veloce e senza loop.
        !for .p, 0, 7 {
                clc
                !for .c, 39, 0 {
                        rol line + .p + .c*8
                }
        }
        rts

; ---------------------------------------------------------------------
;  insert_char: disegna il prossimo glifo nell'ultima cella (destra)
; ---------------------------------------------------------------------
insert_char:
        jsr next_glyph
        lda #<(line + (CELLS-1)*8)
        sta zp_dst
        lda #>(line + (CELLS-1)*8)
        sta zp_dst+1
        jsr draw_glyph
        rts

; ---------------------------------------------------------------------
;  fill_line: riempie le 40 celle della riga col messaggio ripetuto
; ---------------------------------------------------------------------
fill_line:
        lda #<line
        sta zp_dst
        lda #>line
        sta zp_dst+1
        lda #$00
        sta msg_idx
        ldx #CELLS
fl_loop:
        jsr next_glyph
        jsr draw_glyph
        lda zp_dst
        clc
        adc #$08
        sta zp_dst
        bcc fl_skip
        inc zp_dst+1
fl_skip:
        dex
        bne fl_loop
        rts

; ---------------------------------------------------------------------
;  next_glyph: mette in zp_src il prossimo glifo del messaggio e
;  avanza msg_idx di 2. Al terminatore (word 0) riparte dall'inizio.
;  Non modifica X (cosi' fill_line puo' usarlo come contatore).
; ---------------------------------------------------------------------
next_glyph:
        ldy msg_idx
        lda scroll_message,y
        sta zp_src
        lda scroll_message+1,y
        sta zp_src+1
        ora zp_src
        bne ng_ok
        ldy #$00              ; terminatore: wrap all'inizio
        sty msg_idx
        lda scroll_message,y
        sta zp_src
        lda scroll_message+1,y
        sta zp_src+1
ng_ok:
        lda msg_idx
        clc
        adc #$02
        sta msg_idx
        rts

; ---------------------------------------------------------------------
;  draw_glyph: copia un glifo 8x8 da (zp_src) a (zp_dst), 8 byte
; ---------------------------------------------------------------------
draw_glyph:
        ldy #$00
dg_loop:
        lda (zp_src),y        ; riga Y del glifo
        sta (zp_dst),y        ; riga Y della cella nel bitmap
        iny
        cpy #$08
        bne dg_loop
        rts

; ---------------------------------------------------------------------
;  clear_bitmap: azzera $2000-$3FFF (32 pagine = 8192 byte)
; ---------------------------------------------------------------------
clear_bitmap:
        lda #$00
        sta zp_dst
        lda #$20
        sta zp_dst+1
        ldy #$00
        tya                   ; A = 0
        ldx #$20              ; 32 pagine
cb_loop:
        sta (zp_dst),y
        iny
        bne cb_loop
        inc zp_dst+1
        dex
        bne cb_loop
        rts

; ---------------------------------------------------------------------
;  fill_screen: riempe la video matrix ($0400-$07FF) con $16
; ---------------------------------------------------------------------
fill_screen:
        lda #$16              ; nibble alto 1 (bianco), basso 6 (blu)
        ldx #$00
fs_loop:
        sta SCREEN+$000,x
        sta SCREEN+$100,x
        sta SCREEN+$200,x
        sta SCREEN+$300,x
        inx
        bne fs_loop
        rts

; ---------------------------------------------------------------------
;  Messaggio dello scroller: "HELLO, WORLD!" seguito da spazi.
;  Sequenza di puntatori (16 bit) ai glifi, terminata da una word 0.
; ---------------------------------------------------------------------
scroll_message:
        !word glyph_H, glyph_E, glyph_L, glyph_L, glyph_O, glyph_COMMA
        !word glyph_SPACE
        !word glyph_W, glyph_O, glyph_R, glyph_L, glyph_D, glyph_EXCL
        !word glyph_SPACE, glyph_SPACE, glyph_SPACE, glyph_SPACE
        !word $0000

; ---------------------------------------------------------------------
;  Font 8x8 disegnato a mano (bit 7 = pixel piu' a sinistra)
; ---------------------------------------------------------------------
glyph_SPACE:
        !byte $00,$00,$00,$00,$00,$00,$00,$00
glyph_EXCL:
        !byte $18,$18,$18,$18,$18,$00,$18,$00
glyph_COMMA:
        !byte $00,$00,$00,$00,$00,$18,$18,$30
glyph_H:
        !byte $81,$81,$81,$ff,$81,$81,$81,$00
glyph_E:
        !byte $ff,$80,$80,$fe,$80,$80,$ff,$00
glyph_L:
        !byte $80,$80,$80,$80,$80,$80,$ff,$00
glyph_O:
        !byte $7e,$81,$81,$81,$81,$81,$7e,$00
glyph_W:
        !byte $81,$81,$81,$a5,$a5,$db,$99,$00
glyph_R:
        !byte $fe,$81,$81,$fe,$90,$88,$84,$00
glyph_D:
        !byte $fc,$82,$81,$81,$81,$82,$fc,$00
