CC = iverilog
OBJ = test_rtl
FLAGS = -Wall -Winfloop
SOURCE = ../scripts/source.f
TOP = tb

all:
	$(CC) $(FLAGS) -f $(SOURCE) -y ../rtl -s $(TOP) -o $(OBJ)
	vvp $(OBJ)
clean:
	rm -rf $(OBJ) csrc DVEfiles new_datamem.txt simv simv.daidir *.log ucli.key *.vpd
wave:
	gtkwave $(OBJ).vpd config.gtkw &
