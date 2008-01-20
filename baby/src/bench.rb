require "benchmark.rb"

$labels = {}
$counts = Hash.new { 0 }

def bench label
   tms = $labels[label] || Benchmark::Tms.new(0.0, 0.0, 0.0, 0.0, 0.0, label)
   ret = nil
   $counts[label] += 1
   $labels[label] = tms.add {
      ret = yield
   }
   ret
end

def print_bm_report
   field_width = ($labels.keys.map{|s|s.length}.max || 0) + 1
   str = (" " * [(field_width - ("    ".length)), 0].max) + Benchmark::Tms::CAPTION
   total  = Benchmark::Tms.new(0.0, 0.0, 0.0, 0.0, 0.0, nil)
   values = $labels.values
   values << $labels.values.inject(total) { |t, tms| t+tms }
   $labels.each_pair { |label, tms| tms.instance_eval { @label = label } }
   str << values.map {
      |tms|
      arr   = tms.to_a
      label = arr.shift || "total"
      tms = Benchmark::Tms.new(*(arr + []))
      "#{label.rjust(field_width)}#{tms.to_s.chomp} : calls #{$counts[label]}"
   }.join("\n")
   STDERR.puts str
end

