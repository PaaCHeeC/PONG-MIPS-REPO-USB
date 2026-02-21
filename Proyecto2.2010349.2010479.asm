# UNIVERSIDAD SIMON BOLIVAR
# DEPARTAMENTE DE COMPUTACION Y TECNOLOGIA DE LA INFORMACION
# CI-3815: ORGANIZACION DEL COMPUTADOR
#
# PROYECTO 2:  PONG (MIPS)
# AUTORES:     Victor Hernandez (20-10349) y Angel Pacheco (20-10479)
# FECHA:       Diciembre 2025
#
# DESCRIPCION GENERAL:
# Este programa implementa una version del juego Pong utilizando el simulador 
# "Keyboard and Display MMIO" de MARS. Actua como un controlador de dispositivo
# (driver), manipulando directamente la memoria de video para lograr un 
# renderizado en tiempo real sin usar las llamadas de sistema de consola estandar.

.data
    # CONFIGURACION Y CONSTANTES
    ANCHO:      .word 24			# Ancho total del buffer (23 chars + \n)
    ALTO:       .word 8			# Altura total (filas 0-7)
    
    # VARIABLES DE ESTADO DEL JUEGO
    game_mode:  .word 0       		# 1=1P, 2=2P
    current_lvl:.word 1       		# 1=Normal, 2=Obstaculos
    
    # ESTADO DE LA BOLA:
    # 0 = Posicion P1 (Pegada a la izquierda)
    # 1 = En juego (Moviendose)
    # 2 = Posicion P2 (Pegada a la derecha)
    ball_state: .word 0
    
    # VECTORES DE FISICA Y POSICIONAMIENTO
    ballX:      .word 1			# Posicion X inicial (Delante de P1)
    ballY:      .word 3       		# Posicion Y inicial (Centro)
    balldX:     .word 1      		# Velocidad X (+1 derecha, -1 izquierda) 
    balldY:     .word -1      		# Velocidad Y (+1 abajo, -1 arriba)
    
    paddle1Y:   .word 3       		# Posicion Y paleta 1
    paddle2Y:   .word 3       		# Posicion Y paleta 2
    
    # VARIABLES DE CONTROL E IA
    paddle2_dir:.word 0			# Direccion actual de la IA
    last_dir_p1:.word -1			# MEmoria de direccion P1 para saques
    last_dir_p2:.word -1			# Memoria de direccion P2 para saques
    
    score1:     .word 0			# Puntaje del jugador 1
    score2:     .word 0			# Puntaje del jugador 2
    last_time:  .word 0       		# Marca de tiempo para control de frames

    # BUFFER PARA VIDEO (LIENZO) Y MENSAJES
    pantalla: 
        .ascii  "######### 0-0 #########\n"
        .ascii  "           |           \n"
        .ascii  "           |           \n"
        .ascii  "           |           \n"
        .ascii  "           |           \n"
        .ascii  "           |           \n"
        .ascii  "           |           \n"
        .ascii  "#######################\n"
        .asciiz "" 

    menu_msg:   .asciiz "MODO: (1) 1 Jugador, (2) 2 Jugadores\n"
    
    # String largo de saltos de linea para "limpiar" la consola MMIO visualmente
    clear_msg:  .asciiz "\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n\n" 

    lvl2_msg:   .asciiz "\n*** NIVEL 2: OBSTACULOS ***\n"
    win_p1_msg: .asciiz "\nVICTORIA FINAL: JUGADOR 1\n"
    win_p2_msg: .asciiz "\nVICTORIA FINAL: JUGADOR 2\n"

.text
.globl main

# RUTINA PRINCIPAL
main:
    # Semilla Random (Syscall 30 + 40)
    li     $v0, 30			# Obtener tiempo
    syscall
    move   $a1, $a0			# Mover tiempo a argumento semilla
    li     $v0, 40			# Establecer velocidad
    li     $a0, 0			# ID del generador
    syscall
    
    # Inicializar time
    li     $v0, 30			# Obtener tiempo
    syscall
    sw     $a0, last_time	# Guardar timepo inicial

    # Mostrar menu en MMIO
    la     $a0, menu_msg
    jal    print_mmio      

# BUCLE DE MENU (ESPERAR ACTIVA DE TECLA)
wait_menu:
    jal    check_input			# Verificar teclado MMIO
    beqz   $v0, wait_menu			# Si no hay tecla, repetir
    
    subi   $t0, $v0, 48   		# Convertir ASCII a entero ('0'=48)
    
    # Validacion de rango (Solo 1 a 2)
    li     $t1, 1
    blt    $t0, $t1, wait_menu		# Si entrada < 1, ignorar
    li     $t1, 2
    bgt    $t0, $t1, wait_menu		# Si entrada > 2, ignorar
    
    # Seleccion valida
    sw     $t0, game_mode
    
    # Preparar pantalla de juego
    jal    update_score_display

# BUCLE PRINCIPAL DEL JUEGO (GAME LOOP)
game_loop:
    # CONTROL DE TIEMPO (REFRESCAMIENTO 200ms)
wait_tick:
    li     $v0, 30       			# Obtener tiempo (milisegundos)   
    syscall             
    
    lw     $t0, last_time			# Cargar ultima marca de tiempo
    sub    $t1, $a0, $t0   	 	# Calcular delta
    
    li     $t2, 200      			# Velocidad esperada   
    blt    $t1, $t2, wait_tick 		# Si delta < 200, seguir esperando
    
    sw     $a0, last_time   		# Actualizar marca de tiempo para el sig. frame

    # LECTURA DE INPUTS
    # Incializadas en 0
    li     $s1, 0  			# Accion P1
    li     $s2, 0  			# Accion P2

poll_loop:
    jal    check_input
    beqz   $v0, apply_inputs 		# Si no hay mas teclas en buffer, aplicar logica
    
    move   $t0, $v0			# Mover tecla leida a temporal
    
    # P1 Mapping
    beq    $t0, 119, set_p1_u		# 'w' Arriba
    beq    $t0, 115, set_p1_d		# 's' Abajo
    beq    $t0, 120, set_p1_x 		# 'x' Saque
    
    # P2 Mapping (Solo si Mode == 2)
    lw     $t9, game_mode
    li     $t8, 2
    bne    $t9, $t8, poll_loop 		# Si es 1P, ignorar teclas P2
    
    beq    $t0, 111, set_p2_u 		# 'o' Arriba
    beq    $t0, 107, set_p2_d 		# 'k' Abajo
    beq    $t0, 109, set_p2_m 		# 'm' Saque
    
    j      poll_loop 			# Seguir drenado de buffer

# Setters de Acciones (Optimizan saltos)
set_p1_u: 
    li     $s1, 1 			# P1 Arriba
    j      poll_loop
set_p1_d: 
    li     $s1, 2 			# P1 Abajo
    j      poll_loop
set_p1_x:
    li     $s1, 3			# P1 Saque
    j      poll_loop
set_p2_u: 
    li     $s2, 1 			# P2 Arriba
    j      poll_loop
set_p2_d:
    li     $s2, 2 			# P2 Abajo
    j      poll_loop
set_p2_m:
    li     $s2, 3 			# P2 Saque
    j      poll_loop

# APLICAR LOGICA DE MOVIMIENTO (PALETAS)
apply_inputs:
    # P1 Actions
    beq    $s1, 1, p1_up
    beq    $s1, 2, p1_down
    beq    $s1, 3, p1_serve
    j      check_p2_exec			# Si no hubo input P1, saltar a P2

p1_up:
    li     $t9, -1
    sw     $t9, last_dir_p1		# Guardar ultima direccion (-1)
    lw     $t1, paddle1Y
    li     $t2, 1
    ble    $t1, $t2, check_p2_exec	# Limite superior
    addi   $t1, $t1, -1
    sw     $t1, paddle1Y
    j      check_p2_exec

p1_down:
    li     $t9, 1
    sw     $t9, last_dir_p1		# Guardar ultima direccion (1)
    lw     $t1, paddle1Y
    li     $t2, 6
    bge    $t1, $t2, check_p2_exec	# Limite inferior
    addi   $t1, $t1, 1
    sw     $t1, paddle1Y
    j      check_p2_exec
    
p1_serve:
    lw     $t1, ball_state
    bnez   $t1, check_p2_exec		# Solo servir si ball_state == 0
    li     $t1, 1
    sw     $t1, ball_state		# Estado en juego
    li     $t1, 1
    sw     $t1, balldX			# Direccion X derecha
    lw     $t2, last_dir_p1
    sw     $t2, balldY			# Direccion Y segun movimiento previo
    bnez   $t2, check_p2_exec
    li     $t2, -1			# Default Y arriba si estaba quieto
    sw     $t2, balldY

# P2 Actions
check_p2_exec:
    beq    $s2, 1, p2_up
    beq    $s2, 2, p2_down
    beq    $s2, 3, p2_serve
    j      run_logic

p2_up:
    li     $t9, -1
    sw     $t9, last_dir_p2
    lw     $t1, paddle2Y
    li     $t2, 1
    ble    $t1, $t2, run_logic
    addi   $t1, $t1, -1
    sw     $t1, paddle2Y
    j      run_logic
    
p2_down:
    li     $t9, 1
    sw     $t9, last_dir_p2
    lw     $t1, paddle2Y
    li     $t2, 6
    bge    $t1, $t2, run_logic
    addi   $t1, $t1, 1
    sw     $t1, paddle2Y
    j      run_logic
    
p2_serve:
    lw     $t1, ball_state
    li     $t2, 2
    bne    $t1, $t2, run_logic
    li     $t1, 1
    sw     $t1, ball_state
    li     $t1, -1
    sw     $t1, balldX
    lw     $t2, last_dir_p2
    sw     $t2, balldY

# INTELIGENCIA ARTIFICIAL Y FISCA
run_logic:
    # IA (Solo modo 1)
    lw     $t9, game_mode
    li     $t8, 1
    bne    $t9, $t8, end_input_proc
    jal    update_AI

end_input_proc:
    # LIMPIEZA VISUAL (Borrar rastro anterior)
    lw     $a0, ballX
    lw     $a1, ballY
    li     $a2, 32         		# Espacio ' ' 
    li     $t5, 11
    bne    $a0, $t5, do_clean
    li     $a2, 124 			# Si esta en el medio, dibujar Red '|'
do_clean:
    jal    draw_pixel
    jal    clean_paddle_lanes		# Limpiar columnas de paletas

    # CALCULO DE FISICAS
    jal    update_game_logic
    
    # DIBUJADO DE NUEVO FRAME
    lw     $a0, ballX
    lw     $a1, ballY
    li     $a2, 111 			# Caracter 'o'
    jal    draw_pixel
    
    # Paletas
    lw     $a0, paddle1Y
    jal    draw_paddle1
    lw     $a0, paddle2Y
    jal    draw_paddle2
    
    # Obstaculos (Nivel 2)
    lw     $t0, current_lvl
    li     $t1, 2
    beq    $t0, $t1, draw_obs
    j      skip_obs_draw
draw_obs:
    jal    draw_obstacles
skip_obs_draw:
    # OUTPUT MMIO
    la     $a0, clear_msg   
    jal    print_mmio     		# Limpiar terminal 
    la     $a0, pantalla    
    jal    print_mmio      		# Dibujar frame actual

    j      game_loop			# Repetir bucle

# SUBRUTINAS
# DIBUJAR OBSTACULOS (NIVEL 2)
draw_obstacles:
    addi   $sp, $sp, -4
    sw     $ra, 0($sp)
    
    li     $a0, 11
    li     $a1, 2
    li     $a2, 88  			# Caracter 'X'
    jal    draw_pixel
    
    li     $a0, 11
    li     $a1, 5
    li     $a2, 88  			# Caracter 'X'
    jal    draw_pixel
    
    lw     $ra, 0($sp)
    addi   $sp, $sp, 4
    jr     $ra

# FISICA PREDICTIVA
# Calcula la posicion futura y detecta colisiones
physics_move:
    addi   $sp, $sp, -4
    sw     $ra, 0($sp)
    
    lw     $t0, ballX
    lw     $t1, balldX
    add    $t8, $t0, $t1   		# Futuro X
    
    lw     $t2, ballY
    lw     $t3, balldY
    add    $t9, $t2, $t3   		# Futuro Y
    
    # CHEQUEO DE OBSTACULOS (Nivel 2) 
    lw     $t4, current_lvl
    li     $t5, 2
    bne    $t4, $t5, skip_obs_phys
    
    # Chequeo de obstaculos
    li     $t4, 11
    bne    $t8, $t4, check_o2
    li     $t4, 2
    bne    $t9, $t4, check_o2
    
    # Rebote de obstaculo 1
    li     $t3, 11
    sw     $t3, ballX
    lw     $t3, balldX
    neg    $t3, $t3
    sw     $t3, balldX
    j      end_phys

check_o2: 
    li     $t4, 11
    bne    $t8, $t4, skip_obs_phys
    li     $t4, 5
    bne    $t9, $t4, skip_obs_phys
    
    # Rebote de obstaculo 2
    li     $t3, 11
    sw     $t3, ballX 
    lw     $t3, balldX
    neg    $t3, $t3
    sw     $t3, balldX
    j      end_phys

skip_obs_phys:
    # REBOTES CON PAREDES (TECHO/PISO) 
    li     $t4, 0
    ble    $t9, $t4, hit_ceil
    li     $t4, 7
    bge    $t9, $t4, hit_floor
    j      check_sides

hit_ceil:
    li     $t3, 1
    sw     $t3, balldY			# Invertir Y hacia abajo
    li     $t9, 1           		# Clamp posicion
    j      check_sides	

hit_floor:
    li     $t3, -1
    sw     $t3, balldY			# Invertir Y hacia abajo
    li     $t9, 6           	 	# Clamp posicion
    j      check_sides

check_sides:
    # DETECCION DE GOL 0 PALETA 
    li     $t4, 0
    ble    $t8, $t4, try_hit_p1 		# Si FuturoX <= 0
    li     $t4, 22
    bge    $t8, $t4, try_hit_p2 		# Si FuturoX >= 22
    
    # Si no hay colision lateral, avanzar libremente
    sw     $t8, ballX
    sw     $t9, ballY
    j      end_phys

try_hit_p1:
    lw     $t5, paddle1Y
    bne    $t9, $t5, score_p2_evt
    
    # Contacto exitoso de P1
    li     $t1, 1
    sw     $t1, balldX			# Rebotar hacia derecha
    li     $t0, 1
    sw     $t0, ballX			# Posicionar en X=1
    j      end_phys

try_hit_p2:
    lw     $t5, paddle2Y
    bne    $t9, $t5, score_p1_evt
    
    # Contacto exitoso de P2
    li     $t1, -1
    sw     $t1, balldX			# Rebotar hacia izquierda
    li     $t0, 21          
    sw     $t0, ballX			# Posicionar en X=21
    j      end_phys

score_p1_evt: 
    # Gol P1
    lw     $t4, score1
    addi   $t4, $t4, 1
    sw     $t4, score1
    jal    update_score_display
    
    # Verificar victoria de nivel
    li     $t5, 5
    beq    $t4, $t5, check_level_win
    
    # Reset para saque de P2
    li     $t0, 2			# Estado de bola = P2
    sw     $t0, ball_state
    lw     $t1, paddle2Y
    sw     $t1, ballY
    li     $t2, 21          		# Bola pegada a P2
    sw     $t2, ballX
    li     $t0, -1			# Reset direccion P2
    sw     $t0, last_dir_p2
    j      end_phys

score_p2_evt: 
    # Gol P2
    lw     $t4, score2
    addi   $t4, $t4, 1
    sw     $t4, score2
    jal    update_score_display
    
    li     $t5, 5
    beq    $t4, $t5, check_level_win
    
    # Reset para saque de P1
    li     $t0, 0			# Estado de bola = P1
    sw     $t0, ball_state
    lw     $t1, paddle1Y
    sw     $t1, ballY
    li     $t2, 1          		# Bola pegada a P1
    sw     $t2, ballX
    j      end_phys

end_phys:
    lw     $ra, 0($sp)
    addi   $sp, $sp, 4
    jr     $ra

# GESTION DE VICTORIA / CAMBIO DE NIVEL 
check_level_win:
    lw     $t0, current_lvl
    li     $t1, 1
    bne    $t0, $t1, final_win
    
    # Transicion a Nivel 2
    la     $a0, lvl2_msg
    jal    print_mmio
       
    li     $t0, 2
    sw     $t0, current_lvl		# Set Nivel 2
    li     $t0, 0			# Reset Scores
    sw     $t0, score1
    sw     $t0, score2
    jal    update_score_display
    
    # Espera 5 segundos
    li     $v0, 30
    syscall
    addi   $t0, $a0, 5000 
wait_lvl:
    li     $v0, 30
    syscall
    blt    $a0, $t0, wait_lvl
    
    # Reset Total
    li     $t0, 0
    sw     $t0, ball_state
    lw     $t1, paddle1Y
    sw     $t1, ballY
    li     $t2, 1
    sw     $t2, ballX
    
    # Reset Timer para evitar salto brusco
    li     $v0, 30
    syscall
    sw     $a0, last_time
    
    j      end_phys

final_win:
    lw     $t4, score1
    li     $t5, 5
    beq    $t4, $t5, p1_wins
    j      p2_wins

p1_wins:
    la     $a0, win_p1_msg
    jal    print_mmio
    j      game_over
p2_wins:
    la     $a0, win_p2_msg
    jal    print_mmio
    j      game_over

# LOGICA DE ACTUALIZACION GENERAL 
update_game_logic:
    addi   $sp, $sp, -4
    sw     $ra, 0($sp)
    
    lw     $t0, ball_state
    beqz   $t0, stick_p1			# Si estado 0, pegar a P1
    li     $t1, 2
    beq    $t0, $t1, stick_p2		# Si estado 2, pegar a P2
    
    jal    physics_move			# Si estado 1, mover bola
    j      end_lg
    
stick_p1:
    lw     $t1, paddle1Y
    sw     $t1, ballY			# Y bola = Y paleta1
    li     $t2, 1
    sw     $t2, ballX			# X bola = 1
    j      end_lg
    
stick_p2:
    lw     $t1, paddle2Y
    sw     $t1, ballY			# Y bola = Y paleta2
    li     $t2, 21
    sw     $t2, ballX			# X bola = 21
    j      end_lg
    
end_lg:
    lw     $ra, 0($sp)
    addi   $sp, $sp, 4
    jr     $ra

# INTELIGENCIA ARTIFICIAL (IA) 
update_AI:
    addi   $sp, $sp, -4
    sw     $ra, 0($sp)
    
    # Random 1: Moverse o Repetir
    li     $a1, 100
    jal    get_random
    andi   $t0, $a0, 1
    beqz   $t0, do_ia_move
    
    # Random 2: Moverse o Detenerse
    li     $a1, 100
    jal    get_random
    andi   $t0, $a0, 1
    beqz   $t0, stop_ia
    
    # Random 3: Arriba o Abajo
    li     $a1, 100
    jal    get_random
    andi   $t0, $a0, 1
    beqz   $t0, up_ia
    j      down_ia

stop_ia:
    li     $t1, 0
    sw     $t1, paddle2_dir
    j      do_ia_move
up_ia:
    li     $t1, -1
    sw     $t1, paddle2_dir
    j      do_ia_move
down_ia:
    li     $t1, 1
    sw     $t1, paddle2_dir
    
do_ia_move:
    lw     $t0, paddle2Y
    lw     $t1, paddle2_dir
    
    # Limites de la IA (0-7)
    li     $t2, 1
    ble    $t0, $t2, chk_u_ia
    li     $t2, 6
    bge    $t0, $t2, chk_d_ia
    j      ap_ia
    
chk_u_ia:
    bltz   $t1, fin_ia
    j      ap_ia
chk_d_ia:
    bgtz   $t1, fin_ia
    j      ap_ia
    
ap_ia:
    add    $t0, $t0, $t1
    sw     $t0, paddle2Y
    
    # Logica de Auto-Saque
    lw     $t9, ball_state
    li     $t8, 2
    bne    $t9, $t8, fin_ia		# Si bola no es mia, fin
    
    li     $t9, 1
    sw     $t9, ball_state		# Sacar bola
    li     $t9, -1
    sw     $t9, balldX			# Hacia la izquierda
    lw     $t9, paddle2_dir
    bnez   $t9, set_ia_s
    li     $t9, 1 			# Default saque
set_ia_s:
    sw     $t9, balldY
fin_ia:
    lw     $ra, 0($sp)
    addi   $sp, $sp, 4
    jr     $ra

# PRINT MMIO (IMPRESION EN SIMULADOR) 
print_mmio:
    move   $t0, $a0
    li     $t1, 0xffff0008		# Direccion Control Transmitter
    li     $t2, 0xffff000c		# Direccion Data Transmitter
pl_loop:
    lb     $t3, 0($t0)			# Cargar char del string
    beqz   $t3, pl_end			# Fin de string (null terminator)
wait_disp:
    lw     $t4, 0($t1)			# Leer control
    andi   $t4, $t4, 1			# Verificar bit "Ready"
    beqz   $t4, wait_disp			# Esperar si no esta listo
    sb     $t3, 0($t2)			# Escribir char en data
    addi   $t0, $t0, 1			# Siguiente char
    j      pl_loop
pl_end:
    jr     $ra

# DIBUJAR PIXEL EN BUFFER 
draw_pixel:
    # Bounds Checking
    bltz   $a0, abt_drw
    li     $t0, 23
    bgt    $a0, $t0, abt_drw
    bltz   $a1, abt_drw
    li     $t0, 7
    
    # Calcular Offset: Base + (Y * 24) + X
    bgt    $a1, $t0, abt_drw
    la     $t0, pantalla
    mul    $t1, $a1, 24
    add    $t1, $t1, $a0
    add    $t0, $t0, $t1
    
    # No escribir saltos de linea (ASCII 35 '#')
    lb     $t3, 0($t0)
    li     $t4, 35
    beq    $t3, $t4, abt_drw
    
    sb     $a2, 0($t0)			# Escribir pixel
abt_drw:
    jr     $ra

# LIMPIAR COLUMNAS DE PALETAS 
clean_paddle_lanes:
    la     $t0, pantalla
    li     $t1, 1			# Y iterador
    li     $t2, 7			# Limite Y
cl_loop:
    bge    $t1, $t2, cl_end
    mul    $t3, $t1, 24
    add    $t3, $t3, $t0
    li     $t4, 32			# Espacio en blanco ' '
    
    # Limpiar columna 0 (P1)
    lb     $t5, 0($t3)
    li     $t6, 35			# '#'
    beq    $t5, $t6, sk0			# No borrar paredes
    sb     $t4, 0($t3)
sk0:
    # Limpiar columna 22 (P2)
    lb     $t5, 22($t3)
    beq    $t5, $t6, sk22
    sb     $t4, 22($t3)
sk22:
    addi   $t1, $t1, 1
    j      cl_loop
cl_end:
    jr     $ra

# DIBUJAR PALETAS ('H')  
draw_paddle1: 
    move   $t8, $a0
    li     $a2, 72			# 'H'
    move   $a1, $t8
    li     $a0, 0			# Columna 0
    addi   $sp, $sp, -4
    sw     $ra, 0($sp)
    jal    draw_pixel
    lw     $ra, 0($sp)
    addi   $sp, $sp, 4
    jr     $ra

draw_paddle2:
    move   $t8, $a0
    li     $a2, 72 			# 'H'
    move   $a1, $t8
    li     $a0, 22			# Columna 22
    addi   $sp, $sp, -4
    sw     $ra, 0($sp)
    jal    draw_pixel
    lw     $ra, 0($sp)
    addi   $sp, $sp, 4
    jr     $ra

# GENERADOR RANDOM 
get_random:
    li     $v0, 42
    li     $a0, 0
    syscall
    jr     $ra

# LEER TECLADO MMIO 
check_input:
    li     $t0, 0xffff0000		# Control Receiver
    lw     $t1, 0($t0)
    andi   $t1, $t1, 1			# Check Ready Bit
    beqz   $t1, no_key
    lw     $v0, 4($t0)			# Leer Data Receiver
    jr     $ra				# Mascara para limpiar basura
no_key:
    li     $v0, 0
    jr     $ra

# ACTUALIZAR SCOREBOARD 
update_score_display:
    la     $t0, pantalla
    lw     $t1, score1
    addi   $t1, $t1, 48			# Int to ASCII
    sb     $t1, 10($t0)			# Posicion score 1
    lw     $t2, score2
    addi   $t2, $t2, 48			# Int to ASCII
    sb     $t2, 12($t0)			# Posicion score 2
    jr     $ra

game_over:
    li     $v0, 10			# Salida
    syscall
