all: build

build:
	odin build . -o:speed

debug:
	odin build . -o:minimal

clean:
	rm -f fast
