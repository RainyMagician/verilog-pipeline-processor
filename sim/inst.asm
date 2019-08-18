.data
315

.text
main:
  addi $sp, $0, 4095
	lw $a0, 0($0)
	
	jal factors
	j end
	
factors:
	beq $a0, $0, end
	addi $sp, $sp, -20
	sw $ra, 0($sp)
	sw $a0, 4($sp)	# $a0 = num to be factored
	sw $a1, 8($sp)
	sw $a2, 12($sp)
	sw $a3, 16($sp)
	
	addi $a1, $0, 4	# $a1 = j=0
	addi $a2, $0, 1	# $a2 = i=1
	loop_0:
		beq $a2, $a0, end_0	# if i<=n
		jal modulo	# $a3 = remainder
		bne $a3, $0, skip	# if remnainder == 0
			sw $a2, 0($a1)	# factors[j] = i
			addi $a1, $a1, 4	# j++
		skip:
		addi $a2, $a2, 1	# i++
		j loop_0
	end_0:
	sw $a0, 0($a1)
	
	lw $ra, 0($sp)
	lw $a0, 4($sp)
	lw $a1, 8($sp)
	lw $a2, 12($sp)
	lw $a3, 16($sp)
	addi $sp, $sp, 20
	jr $ra
	
modulo:
	addi $sp, $sp, -8
	sw $a0, 0($sp)
	sw $a1, 4($sp)

	loop_1:
		sub $a0, $a0, $a2
		slt $a1, $a0, $0
		bne $a1, $0, end_1
		j loop_1
	end_1:
	add $a3, $a0, $a2
	
	lw $a0, 0($sp)
	lw $a1, 4($sp)
	addi $sp, $sp, 8
	jr $ra
	
end:
