all: out1 out2 out3
	cat out1 out2 out3

clean:
	rm -f out1 out2 out3

out1: basic.rb
	ruby basic.rb > out1

out2: perf.rb
	ruby perf.rb > out2

out3: big.rb
	ruby big.rb > out3