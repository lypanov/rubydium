require 'test/unit'
$: << "lib/"
require 'ruby_parser'

class TestRubyParser < Test::Unit::TestCase

  def setup
    @processor = RubyParser.new
  end

  def test_block_append
    head = s(:args)
    tail = s(:zsuper)
    expected = s(:block, s(:args), s(:zsuper))
    assert_equal expected, @processor.block_append(head, tail)
  end

  def test_block_append_block
    head = s(:block, s(:args))
    tail = s(:zsuper)
    expected = s(:block, s(:args), s(:zsuper))
    assert_equal expected, @processor.block_append(head, tail)
  end

  def test_block_append_tail_block
    head = s(:vcall, :f1)
    tail = s(:block, s(:undef, s(:lit, :x)), s(:undef, s(:lit, :y)))
    expected = s(:block,
                 s(:vcall, :f1),
                 s(:block, s(:undef, s(:lit, :x)), s(:undef, s(:lit, :y))))
    assert_equal expected, @processor.block_append(head, tail)
  end

  def test_block_append_begin_begin
    head = s(:begin, s(:args))
    tail = s(:begin, s(:args))
    expected = s(:block, s(:args), s(:begin, s(:args)))
    assert_equal expected, @processor.block_append(head, tail)
  end

  def test_block_append_nil_head
    head = nil
    tail = s(:zsuper)
    expected = s(:zsuper)
    assert_equal expected, @processor.block_append(head, tail)
  end

  def test_block_append_nil_tail
    head = s(:args)
    tail = nil
    expected = s(:args)
    assert_equal expected, @processor.block_append(head, tail)
  end

  def test_call_env
    @processor.env[:a] = :lvar
    expected = s(:call, s(:lvar, :a), :happy)

    assert_equal expected, @processor.parse('a.happy')
  end

  def test_do_bug # TODO: rename
    rb = "a 1\na.b do |c|\n  # do nothing\nend"
    pt = s(:block,
           s(:fcall, :a, s(:array, s(:lit, 1))),
           s(:iter, s(:call, s(:vcall, :a), :b), s(:dasgn_curr, :c)))

    assert_equal pt, @processor.parse(rb)
  end

  def test_lasgn_env
    rb = 'a = 42'
    pt = s(:lasgn, :a, s(:lit, 42))
    expected_env = { :a => :lvar }
    
    assert_equal pt, @processor.parse(rb)
    assert_equal expected_env, @processor.env.all
  end

  def test_logop_12
    lhs = s(:lit, 1)
    rhs = s(:lit, 2)
    exp = s(:and, s(:lit, 1), s(:lit, 2))

    assert_equal exp, @processor.logop(:and, lhs, rhs)
  end

  def test_logop_12_3
    lhs = s(:and, s(:lit, 1), s(:lit, 2))
    rhs = s(:lit, 3)
    exp = s(:and, s(:lit, 1), s(:and, s(:lit, 2), s(:lit, 3)))

    assert_equal exp, @processor.logop(:and, lhs, rhs)
  end

  def test_logop_123_4
    lhs = s(:and, s(:lit, 1), s(:and, s(:lit, 2), s(:lit, 3)))
    rhs = s(:lit, 4)
    exp = s(:and,
            s(:lit, 1),
            s(:and,
              s(:lit, 2),
              s(:and,
                s(:lit, 3),
                s(:lit, 4))))

    assert_equal exp, @processor.logop(:and, lhs, rhs)
  end

  def test_logop_1234_5
    lhs = s(:and, s(:lit, 1), s(:and, s(:lit, 2), s(:and, s(:lit, 3), s(:lit, 4))))
    rhs = s(:lit, 5)
    exp = s(:and,
            s(:lit, 1),
            s(:and,
              s(:lit, 2),
              s(:and,
                s(:lit, 3),
                s(:and,
                  s(:lit, 4),
                  s(:lit, 5)))))

    assert_equal exp, @processor.logop(:and, lhs, rhs)
  end

  def test_logop_nested_mix
    lhs = s(:or, s(:vcall, :a), s(:vcall, :b))
    rhs = s(:and, s(:vcall, :c), s(:vcall, :d))
    exp = s(:or,
            s(:or, s(:vcall, :a), s(:vcall, :b)),
            s(:and, s(:vcall, :c), s(:vcall, :d)))

    lhs.paren = true
    rhs.paren = true

    assert_equal exp, @processor.logop(:or, lhs, rhs)
  end

  def test_literal_concat_str_evstr
    lhs, rhs = s(:str, ""), s(:evstr, s(:str, "blah"))

    assert_equal s(:str, "blah"), @processor.literal_concat(lhs, rhs)
  end

  def test_literal_concat_evstr_evstr
    lhs, rhs = s(:evstr, s(:lit, 1)), s(:evstr, s(:lit, 2))
    expected = s(:dstr, "", s(:evstr, s(:lit, 1)), s(:evstr, s(:lit, 2)))

    assert_equal expected, @processor.literal_concat(lhs, rhs)
  end

  def test_literal_concat_dstr_evstr
    lhs, rhs = s(:dstr, "a"), s(:evstr, s(:vcall, :b))
    expected = s(:dstr, "a", s(:evstr, s(:vcall, :b)))

    assert_equal expected, @processor.literal_concat(lhs, rhs)
  end

  def test_literal_concat_dstr_dstr
    lhs      = s(:dstr, "Failed to download spec ",
                 s(:evstr, s(:vcall, :spec_name)),
                 s(:str, " from "),
                 s(:evstr, s(:vcall, :source_uri)),
                 s(:str, ":\n"))
    rhs      = s(:dstr, "\t",
                 s(:evstr, s(:call, s(:ivar, :@fetch_error), :message)))
    expected = s(:dstr, "Failed to download spec ",
                 s(:evstr, s(:vcall, :spec_name)),
                 s(:str, " from "),
                 s(:evstr, s(:vcall, :source_uri)),
                 s(:str, ":\n"),
                 s(:str, "\t"),
                 s(:evstr, s(:call, s(:ivar, :@fetch_error), :message)))

    assert_equal expected, @processor.literal_concat(lhs, rhs)
  end

  def test_str_pct_Q_nested
    rb = "%Q[before [#\{nest}] after]"
    pt = s(:dstr, "before [", s(:evstr, s(:vcall, :nest)), s(:str, "] after"))

    assert_equal pt, @processor.parse(rb)
  end

  def test_str_str
    rb = "\"a #\{'b'}\""
    pt = s(:str, "a b")

    assert_equal pt, @processor.parse(rb)
  end

  def test_str_str_str
    rb = "\"a #\{'b'} c\""
    pt = s(:str, "a b c")

    assert_equal pt, @processor.parse(rb)
  end

  def test_dstr_str
    rb = "\"#\{'a'} b\""
    pt = s(:str, "a b")

    assert_equal pt, @processor.parse(rb)
  end

  def test_str_evstr
    rb = "\"a #\{b}\""
    pt = s(:dstr, "a ", s(:evstr, s(:vcall, :b)))

    assert_equal pt, @processor.parse(rb)
  end

  def test_dstr_evstr
    rb = "\"#\{'a'}#\{b}\""
    pt = s(:dstr, "a", s(:evstr, s(:vcall, :b)))

    assert_equal pt, @processor.parse(rb)
  end

  def test_evstr_str
    rb = "\"#\{a} b\""
    pt = s(:dstr, "", s(:evstr, s(:vcall, :a)), s(:str, " b"))

    assert_equal pt, @processor.parse(rb)
  end

  def test_evstr_evstr
    rb = "\"#\{a}#\{b}\""
    pt = s(:dstr, "", s(:evstr, s(:vcall, :a)), s(:evstr, s(:vcall, :b)))

    assert_equal pt, @processor.parse(rb)
  end


  def test_dasgn_icky2
    rb = "a do\n  v = nil\n  begin\n    yield\n  rescue Exception => v\n    break\n  end\nend"
    pt = s(:iter,
           s(:fcall, :a),
           nil,
           s(:block,
             s(:dasgn_curr, :v, s(:nil)),
             s(:begin,
               s(:rescue,
                 s(:yield),
                 s(:resbody,
                   s(:array, s(:const, :Exception)),
                   s(:block, s(:dasgn_curr, :v, s(:gvar, :$!)), s(:break)))))))

    assert_equal pt, @processor.parse(rb)
  end

  def test_list_append
    lhs, rhs = s(:array, s(:lit, :iter)), s(:when, s(:const, :BRANCHING), nil)
    expected = s(:array, s(:lit, :iter), s(:when, s(:const, :BRANCHING), nil))

    assert_equal expected, @processor.list_append(lhs, rhs)
  end
end