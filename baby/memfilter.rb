#!/usr/bin/env ruby
mem_addrs = {}
mem_addrs = {"0" => "NULL"}
STDIN.each_line {
   |line|
   line.scan(/((.*?)MEM:(\d+)|(.*$))/) {
      |part|
      if part[3]
         print part[3]
      else
         addr = part[2]
         print part[1]
         if not (mem_addrs.has_key? addr)
            mem_addrs[addr] = "ADDR##{mem_addrs.keys.size.to_s * 4}"
         end
         print mem_addrs[addr]
      end
   }
   puts
}
