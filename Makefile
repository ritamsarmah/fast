.PHONY: all debug release clean

OUT := fast

all: debug

debug:
	odin build . -debug -o:none -out:$(OUT)

release:
	odin build . -o:speed -out:$(OUT)

clean:
	rm -f $(OUT)
