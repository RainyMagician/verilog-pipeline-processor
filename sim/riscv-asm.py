#! /usr/bin/python

"""
NAME
	riscv-asm
SYNOPSIS
	run riscv-asm.py
DESCRIPTION
	DISCLAIMER:
	I provide no guarantees for weird coding styles.
	Use at your own risk.

	Converts an assembly file written in the MIPS instruction set to
	RISC-V machine code.

	Uses standard MIPS language.
		$d for register (decimal or labels allowed)
			for labels, see 'reg_label' below or Mars

			IMPORTANT CHANGE: $ra = $1; $at = $31

		d, 0x, 0b, 0o for constants allowed
	Single line comments only ('#', ';', or '//')
	Only restriction is ONE inst/label per line.
		i.e.:
			label1: add $1, $2, $3
				not allowed
			label1:
			add $1, $2, $3
				acceptable

	MIPS Directives
	.data [addr]
		Writes succeeding values separated by '\n' to datamem.txt.
		If addr is specified, starts writing at that addr
		By default addr = 0

	.text
		Assembles succeeding lines into instmem.txt


	Input:
		assembly file named "inst.asm" but you can change that to whatever
	Output:
		"instmem.txt": hex dump sorted into 2 bytes per line
		"datamem.txt": hex dump of values after .data sorted into 2 bytes per line
		"debug.txt": if you want to see line-by-line decoding of input file
AUTHOR
	CoE113 2s17-18 riscv assembler
	Created by: Alfred Brian Chua
	email: alfred.brian.chua@eee.upd.edu.ph
	version: 1.1

"""

import sys

# change filename to whatever assembly file to use
filename = "inst.asm"
instfile = open(filename, "r")
hexfile = open("instmem.txt", "w")
debugfile = open("debug.txt", "w")

MEM_DEPTH = 1024*4

reg_label = {
	'zero'	: 0,
	'ra'	: 1,
	'v0'	: 2,
	'v1'	: 3,
	'a0'	: 4,
	'a1'	: 5,
	'a2'	: 6,
	'a3'	: 7,
	't0'	: 8,
	't1'	: 9,
	't2'	: 10,
	't3'	: 11,
	't4'	: 12,
	't5'	: 13,
	't6'	: 14,
	't7'	: 15,
	's0'	: 16,
	's1'	: 17,
	's2'	: 18,
	's3'	: 19,
	's4'	: 20,
	's5'	: 21,
	's6'	: 22,
	's7'	: 23,
	't8'	: 24,
	't9'	: 25,
	'k0'	: 26,
	'k1'	: 27,
	'gp'	: 28,
	'sp'	: 29,
	'fp'	: 30,
	'at'	: 31,
	'0'		: 0,
	'1'		: 1,
	'2'		: 2,
	'3'		: 3,
	'4'		: 4,
	'5'		: 5,
	'6'		: 6,
	'7'		: 7,
	'8'		: 8,
	'9'		: 9,
	'10'	: 10,
	'11'	: 11,
	'12'	: 12,
	'13'	: 13,
	'14'	: 14,
	'15'	: 15,
	'16'	: 16,
	'17'	: 17,
	'18'	: 18,
	'19'	: 19,
	'20'	: 20,
	'21'	: 21,
	'22'	: 22,
	'23'	: 23,
	'24'	: 24,
	'25'	: 25,
	'26'	: 26,
	'27'	: 27,
	'28'	: 28,
	'29'	: 29,
	'30'	: 30,
	'31'	: 31
}

RD = 6
RS1 = 15
RS2 = 20
IMM_UPPER = 20
IMM_LOWER = 11
BIMM_UPPER = 25
BIMM_LOWER = 6
JIMM = 6

instset = {
	'add'   : 0x40000000,
	'sub'   : 0x44000000,
	'slt'   : 0x54000000,
	'addi'  : 0x00000008,
	'slti'  : 0x0000000A,
	'lw'    : 0x00000023,
	'sw'    : 0x0000002B,
	'beq'   : 0x00000004,
	'bne'   : 0x00000005,
	'j'     : 0x00000002,
	'jal'   : 0x00000003,
	'jr'    : 0x10000000
}

instdef = {
	'add'	: "R_type",
	'sub'	: "R_type",
	'slt'	: "R_type",
	'addi'	: "I_type",
	'slti'	: "I_type",
	'lw'	: "M_type",
	'sw'	: "M_type",
	'beq'	: "B_type",
	'bne'	: "B_type",
	'j'		: "J_type",
	'jal'	: "J_type",
	'jr'	: "JR_type",
	'nop'	: "NOP",
	'noop'	: "NOP"
}

label = {}
label_line_no = {}
hex_buf = 0
type = 0
pc = 0
line_no = 0

def findBase(str):
	try:
		n = int(str,10)
		base = 10
	except ValueError:
		try:
			n = int(str,16)
			base = 16
		except ValueError:
			try:
				n = int(str,2)
				base = 2
			except ValueError:
				n = int(str,8)
				base = 8
	return base
	
def hex_to_bytes(h):
	b3 = (h&0xFF000000) >> 24
	b2 = (h&0x00FF0000) >> 16
	b1 = (h&0x0000FF00) >> 8
	b0 = (h&0x000000FF)
	return (b3, b2, b1, b0)
	
def cleanup_str(str):
	clean = str.replace('\n', '\0')
	clean = str.replace(',', ' ')
	clean = clean.expandtabs(1)
	clean = clean.strip()
	return clean
	
def regname_to_int(regname):
	reg_ind = regname.find('$')+1
	if reg_ind == 0:
		print "error @ line {}\n\improper register syntax".format(line_no)
		sys.exit()
	reglbl = regname[reg_ind:]
	val = reg_label.get(reglbl)
	if val == None:
		print "error @ line {}\n\t register {} not found".format(line_no, reglbl)
		sys.exit()
	return val
		
txt_dump = instfile.readlines()
data_dir = False
wr_data = False
datamem = None
addr = 0

# .data check and write
for line in txt_dump:
	line_no += 1
	if line=='\n' or line=='\r\n':
		continue
	clean = cleanup_str(line)
	if clean=='':
		continue
	elif clean[0]=='#' or clean[0]==';' or clean[0:2]=='//':
		continue
	
	if clean.find('.data') >= 0:
		if data_dir:
			print "error @ line {}:\n\t.data directive was already declared".format(line_no)
			sys.exit()
		else:
			data_dir = True
		arg = clean.split()
		try:
			start_addr = int(arg[1], findBase(arg[1]))
		except IndexError:
			start_addr = 0
			pass
		if start_addr > MEM_DEPTH:
			print "start_addr out of bounds"
			sys.exit()
		print "Writing to datamem.txt"
		datamem = open("datamem.txt", "w")
		addr = start_addr
		if start_addr > 0:
			for i in range(start_addr):
				datamem.write("00\n")
		wr_data = True
	elif clean=='.text':
		txt_dump = txt_dump[line_no:]
		leftover = MEM_DEPTH - addr
		for i in range(leftover):
			datamem.write("00\n")
		break
	elif wr_data:
		try:
			val = int(line, findBase(clean))
		except ValueError:
			print "error @ line {}:\n\tdata: {}".format(line_no, line)
			sys.exit()
		if val > 0xFFFFFFFF:
			print "overflow: {}".format(val)
			sys.exit()
		addr += 4
		for b in hex_to_bytes(val):
			datamem.write("{:02X}\n".format(b))

if datamem != None:
	print "Write to datamem.txt finished"
	datamem.close()
print "Beginning assembly..."
# compute all labels first
debugfile.write("# label values\n\n")
save_line = line_no
for line in txt_dump:
	line_no += 1
	if line=='\n' or line=='\r\n':
		continue
	clean = cleanup_str(line)
	if clean=='':
		continue
	elif clean[0]=='#' or clean[0]==';' or clean[0:2]=='//':
		continue

	label_index = clean.find(':')
	if label_index > 0:
		line_label = clean[:label_index]
		if label.has_key(line_label):
			print "error @ line {}\n\label '{}' was previously defined @ line {}".format(line_no, line_label, label_line_no.get(line_label))
			instfile.close()
			hexfile.close()
			debugfile.close()
			sys.exit()
		label[line_label] = pc
		label_line_no[line_label] = line_no
		debugfile.write("{} @ 0x{:04X}\n".format(line_label, pc))
		continue
	else:
		pc += 4

debugfile.write("\n# Instruction decoding\n\n")
type = 0
pc = 0
line_no = save_line
for line in txt_dump:
	line_no += 1
	if line=='\n' or line=='\r\n':
		continue
	
	hex_buf = 0
	clean = cleanup_str(line)
	if clean=='':
		continue
	elif clean[0]=='#' or clean[0]==';' or clean[0:2]=='//':
		continue

	label_index = clean.find(':')
	if label_index > 0:
		line_label = clean[:label_index]
		debugfile.write("{}:\n".format(line_label))
		continue
	
	debugfile.write("line {: 4}: {}".format(line_no, line))
	arg = clean.split()
	arg[0] = arg[0].lower()
	type = instdef.get(arg[0])
	if type == 'NOP':
		hexfile.write("00\n00\n00\n00\n")
		debugfile.write("{:04X}: 00000000\n\n".format(pc))
		pc = pc + 4
		continue
	elif type == None:
		print "error @ line {}\n\t{} undefined".format(line_no, arg[0])
		break
	
	imm_count = 0
	reg_count = 0
	reg_ind = 0
	if type == 'R_type':
		rd = regname_to_int(arg[1])
		rs1 = regname_to_int(arg[2])
		rs2 = regname_to_int(arg[3])
	elif type == 'I_type':
		rd = regname_to_int(arg[1])

		try:
			base = findBase(arg[2])
			imm = int(arg[2],base)
			imm_count += 1
		except ValueError:
			rs1 = regname_to_int(arg[2])
			reg_count += 1
			pass
		
		try:
			base = findBase(arg[3])
			if imm_count > 0:
				print "error @ line {}:\n\t I-type inst format needs 1 $r and 1 16b'imm".format(line_no)
				break
			imm = int(arg[3],base)
		except ValueError:
			rs1 = regname_to_int(arg[3])
			if reg_count > 0:
				print "error @ line {}:\n\t I-type inst format needs 1 $r and 1 16b'imm".format(line_no)
				break
			pass
	elif type == 'B_type':
		rs1 = regname_to_int(arg[1])
		rs2 = regname_to_int(arg[2])

		target_pc = label.get(arg[3])
		if target_pc == None:
			print "error @ line {}\n\B_type undefined label \"{}\"".format(line_no, arg[3])
			break
		offset = target_pc - pc
	elif type == 'M_type':
		rd = regname_to_int(arg[1])
		
		if arg[2].find('(') < 0:
			print "error @ line {}\n\tlw/sw address syntax error".format(line_no)
			break
		arg[2] = arg[2].replace('(', ' ')
		arg[2] = arg[2].replace(')', ' ')
		mem_access = arg[2].split()
		
		try:
			base = findBase(mem_access[0])
			imm = int(mem_access[0],base)
			imm_count += 1
		except ValueError:
			rs1 = regname_to_int(mem_access[0])
			reg_count += 1
			pass
		
		try:
			base = findBase(mem_access[1])
			if imm_count > 0:
				print "error @ line {}:\n\t I-type inst format needs 1 $r and 1 16b'imm".format(line_no)
				break
			imm = int(mem_access[1],base)
		except ValueError:
			rs1 = regname_to_int(mem_access[1])
			if reg_count > 0:
				print "error @ line {}:\n\t I-type inst format needs 1 $r and 1 16b'imm".format(line_no)
				break
			pass
	elif type == 'J_type':
		target_pc = label.get(arg[1])
		if target_pc == None:
			print "error @ line {}\n\J_type undefined label \"{}\"".format(line_no, arg[1])
			break
		jimm = target_pc
	elif type == 'JR_type':
		rd = regname_to_int(arg[1])
	
	
	hex_buf = instset[arg[0]]
	if type == 'R_type':
		debugfile.write("rd={}, rs1={}, rs2={}\n".format(rd, rs1, rs2))
		debugfile.write("{:07b} {:05b} {:05b} xxxx {:05b} {:06b}\n".format(hex_buf>>25, rs2, rs1, rd, hex_buf&0x3F))
		hex_buf = hex_buf | (rd<<RD) | (rs1<<RS1) | (rs2<<RS2)
	elif type == 'I_type':
		debugfile.write("rd={}, rs1={}, imm={:X}h\n".format(rd, rs1, imm))
		tmp = imm & 0x000F
		imm = (imm & 0xFFF0) >> 4
		debugfile.write("{:07b} {:05b} {:05b} {:04b} {:05b} {:06b}\n".format((imm&0xFE0)>>5, imm&0x1F, rs1, tmp, rd, hex_buf&0x3F))
		hex_buf = hex_buf | (rd<<RD) | (rs1<<RS1) | (imm<<IMM_UPPER) | (tmp<<IMM_LOWER)
	elif type == 'M_type':
		debugfile.write("rd={}, rs1={}, imm={:X}h\n".format(rd, rs1, imm))
		tmp = imm & 0x000F
		imm = (imm & 0xFFF0) >> 4
		debugfile.write("{:07b} {:05b} {:05b} {:04b} {:05b} {:06b}\n".format((imm&0xFE0)>>5, imm&0x1F, rs1, tmp, rd, hex_buf&0x3F))
		hex_buf = hex_buf | (rd<<RD) | (rs1<<RS1) | (imm<<IMM_UPPER) | (tmp<<IMM_LOWER)
	elif type == 'B_type':
		offset = label[arg[3]] - pc - 4
		debugfile.write("rs1={}, rs2={}, offset={:X}h\n".format(rs1, rs2, offset))
		tmp = offset & 0x01FF
		offset = (offset & 0xFE00) >> 9
		debugfile.write("{:07b} {:05b} {:05b} {:04b} {:05b} {:06b}\n".format(offset, rs2, rs1, (tmp&0x1E0)>>5, tmp&0x1F, hex_buf&0x3F))
		hex_buf = hex_buf | (tmp<<BIMM_LOWER) | (rs1<<RS1) | (rs2<<RS2) | (offset<<BIMM_UPPER)
	elif type == 'J_type':
		debugfile.write("imm={:X}h\n".format(jimm))
		debugfile.write("{:028b} {:06b}\n".format(jimm, hex_buf&0x3F))
		hex_buf = hex_buf | (jimm<<JIMM)
	elif type == 'JR_type':
		debugfile.write("rd={}\n".format(rd))
		debugfile.write("{:07b} {} {} {} {:05b} {:06b}\n".format(hex_buf>>25, 'x'*5, 'x'*5, 'x'*4, rd, hex_buf&0x3F))
		hex_buf = hex_buf | (rd<<RD)
		
	debugfile.write("{:04X}: {:08X}\n\n".format(pc, hex_buf))
	for b in hex_to_bytes(hex_buf):
		hexfile.write("{:02X}\n".format(b))
	pc = pc + 4
	
instfile.close()
hexfile.close()
debugfile.close()
print "Assembly finished"
	
