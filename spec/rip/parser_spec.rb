# encoding: utf-8

require 'spec_helper'

describe Rip::Parser do
  context 'some basics' do
    let(:empty) { parser.parse_file(samples_path + 'empty.rip') }

    it 'parses an empty file' do
      expect(empty).to eq('')
    end

    it 'recognizes comments' do
      expect(parser.comment).to parse('# this is a comment').as(:comment => ' this is a comment')
    end

    it 'recognizes various whitespace sequences' do
      {
        [' ', "\t", "\r", "\n", "\r\n"] => :whitespace,
        [' ', "\t\t"]                   => :whitespaces,
        ['', "\n", "\t\r"]              => :whitespaces?,
        [' ', "\t"]                     => :space,
        [' ', "\t\t", "  \t  \t  "]     => :spaces,
        ['', ' ', "  \t  \t  "]         => :spaces?,
        ["\n", "\r", "\r\n"]            => :eol,
        ['', "\n", "\r\r"]              => :eols
      }.each do |whitespaces, method|
        space_parser = parser.send(method)
        whitespaces.each do |space|
          expect(space_parser).to parse(space).as(space)
        end
      end
    end
  end

  describe '#parse' do
    it 'recognizes several statements together' do
      expected = [
        {
          :block => {
            :if => 'if',
            :parameters => [ {:reference => 'true'} ],
            :body => [
              {
                :invocation => {
                  :operand => {:reference => 'lambda'},
                  :operator => {:reference => '='},
                  :argument => {
                    :block => {
                      :lambda_dash => '->',
                      :body => [ {:comment => ' comment'} ]
                    }
                  }
                }
              },
              {
                :invocation => {:reference => 'lambda', :arguments => []}
              }
            ]
          }
        },
        {
          :block => {
            :else => 'else',
            :body => [
              {
                :invocation => {
                  :operand => {:integer => '1'},
                  :operator => {:reference => '+'},
                  :argument => {:integer => '2'}
                }
              }
            ]
          }
        }
      ]

      expect(parser).to parse(<<-RIP).as(expected)
                              if (true) {
                                lambda = -> {
                                  # comment
                                }
                                lambda()
                              } else {
                                1 + 2
                              }
                              RIP
    end
  end

  describe '#reference' do
    it 'recognizes valid references, including predefined references' do
      [
        'name',
        'Person',
        '==',
        'save!',
        'valid?',
        'long_ref-name',
        '*/-+<>&$~%',
        'one_9',
        'É¹ÇÊ‡É¹oÔ€uÉlâˆ€â„¢',
        'nilly',
        'nil',
        'true',
        'false',
        'Kernel',
        'returner'
      ].each do |reference|
        expect(parser.reference).to parse(reference).as(:reference => reference)
      end
    end

    it 'skips invalid references' do
      [
        'one.two',
        '999',
        '6teen',
        'rip rocks',
        'key:value'
      ].each do |non_reference|
        expect(parser.reference).to_not parse(non_reference)
      end
    end
  end

  describe '#block_expression' do
    context 'parameters' do
      it 'recognizes empty blocks' do
        expect(parser.block_expression).to parse('-> {}').as(:block => {:lambda_dash => '->', :body => []})
        expect(parser.block_expression).to parse('class () {}').as(:block => {:class => 'class', :parameters => [], :body => []})
      end

      it 'recognizes blocks with parameter' do
        expect(parser.block_expression).to parse('unless (:name) {}').as(:block => {:unless => 'unless', :parameters => [{:string => 'name'}], :body => []})
      end

      it 'recognizes blocks with default parameter' do
        expected = {
          :block => {
            :lambda_dash => '->',
            :parameters => [
              {
                :invocation => {
                  :operand => {:reference => 'name'},
                  :operator => {:reference => '='},
                  :argument => {:string => 'rip'}
                }
              }
            ],
            :body => []
          }
        }
        expect(parser.block_expression).to parse('-> (name = :rip) {}').as(expected)
      end

      it 'recognizes blocks with multiple parameters' do
        expect(parser.block_expression).to parse('case (one, two) {}').as(:block => {:case => 'case', :parameters => [{:reference => 'one'}, {:reference => 'two'}], :body => []})
      end

      it 'recognizes blocks with parameter and default parameter' do
        expected = {
          :block => {
            :lambda_fat => '=>',
            :parameters => [
              {:reference => 'platform'},
              {
                :invocation => {
                  :operand => {:reference => 'name'},
                  :operator => {:reference => '='},
                  :argument => {:string => 'rip'}
                }
              }
            ],
            :body => []
          }
        }
        expect(parser.block_expression).to parse('=> (platform, name = :rip) {}').as(expected)
      end

      it 'recognizes blocks with block parameters' do
        expected = {
          :block => {
            :class => 'class',
            :parameters => [
              {
                :block => {:class => 'class', :parameters=>[], :body=>[]}
              }
            ],
            :body => []
          }
        }
        expect(parser.block_expression).to parse('class (class () {}) {}').as(expected)
      end
    end

    context 'body' do
      it 'recognizes comments inside blocks' do
        expect(parser.block_expression).to parse(<<-RIP.strip).as(:block => {:if => 'if', :parameters => [{:reference => 'true'}], :body => [{:comment => ' comment'}]})
                                                 if (true) {
                                                   # comment
                                                 }
                                                 RIP
      end

      it 'recognizes references inside blocks' do
        expect(parser.block_expression).to parse('if (true) { name }').as(:block => {:if => 'if', :parameters => [{:reference => 'true'}], :body => [{:reference => 'name'}]})
      end

      it 'recognizes assignments inside blocks' do
        expected = {
          :block => {
            :if => 'if',
            :parameters => [ {:reference => 'true'} ],
            :body => [
              {
                :invocation => {
                  :operand => {:reference => 'x'},
                  :operator => {:reference => '='},
                  :argument => {:string =>"y"}
                }
              }
            ]
          }
        }
        expect(parser.block_expression).to parse('if (true) { x = :y }').as(expected)
      end

      it 'recognizes invocations inside blocks' do
        expect(parser.block_expression).to parse('if (true) { run!() }').as(:block => {:if => 'if', :parameters => [{:reference => 'true'}], :body => [{:invocation => {:reference => 'run!', :arguments => []}}]})
      end

      it 'recognizes operator invocations inside blocks' do
        expected = {
          :block => {
            :if => 'if',
            :parameters => [
              {:reference => 'true'}
            ],
            :body => [
              {
                :invocation => {
                  :operand => {:reference => 'steam'},
                  :operator => {:reference => 'will'},
                  :argument => {:string => 'rise'}
                }
              }
            ]
          }
        }
        expect(parser.block_expression).to parse('if (true) { steam will :rise }').as(expected)
      end

      it 'recognizes literals inside blocks' do
        expect(parser.block_expression).to parse('if (true) { `3 }').as(:block => {:if => 'if', :parameters => [{:reference => 'true'}], :body => [{:character => '3'}]})
      end

      it 'recognizes blocks inside blocks' do
        expected = {
          :block => {
            :if => 'if',
            :parameters => [ {:reference => 'true'} ],
            :body => [
              {
                :block => {
                  :unless => 'unless',
                  :parameters => [ {:reference => 'false'} ],
                  :body => []
                }
              }
            ]
          }
        }
        expect(parser.block_expression).to parse('if (true) { unless (false) { } }').as(expected)
      end
    end
  end

  describe '#simple_expression' do
    it 'recognizes keyword' do
      expect(parser.simple_expression).to parse('return;').as(:keyword => {:return => 'return'})
    end

    it 'recognizes keyword followed by phrase' do
      expect(parser.simple_expression).to parse('exit 0').as(:keyword => {:exit => 'exit'}, :body => {:integer => '0'})
    end

    it 'recognizes keyword followed by parenthesis around phrase' do
      expect(parser.simple_expression).to parse('exit (0)').as(:keyword => {:exit => 'exit'}, :body => {:integer => '0'})
    end

    it 'recognizes list expression' do
      expect(parser.simple_expression).to parse('[]').as(:body => {:list => []})
    end

    context 'with a postfix' do
      it 'recognizes keyword followed by phrase followed by postfix' do
        expect(parser.simple_expression).to parse('exit 1 if (:error)').as(:keyword => {:exit => 'exit'}, :body => {:integer => '1'}, :postfix => {:if => 'if', :argument => {:string => 'error'}})
      end

      it 'recognizes keyword followed by postfix' do
        expect(parser.simple_expression).to parse('return unless (false);').as(:keyword => {:return => 'return'}, :postfix => {:unless => 'unless', :argument => {:reference => 'false'}})
      end

      it 'recognizes phrase followed by postfix' do
        expect(parser.simple_expression).to parse('nil if (empty());').as(:body => {:reference => 'nil'}, :postfix => {:if => 'if', :argument => {:invocation => {:reference => 'empty', :arguments => []}}})
      end
    end
  end

  describe '#phrase' do
    context 'invoking lambdas' do
      it 'recognizes lambda literal invocation' do
        expect(parser.regular_invocation).to parse('-> () {}()').as(:invocation => {:block => {:lambda_dash => '->', :parameters => [], :body => []}, :arguments => []})
      end

      it 'recognizes lambda reference invocation' do
        expect(parser.phrase).to parse('full_name()').as(:invocation => {:reference => 'full_name', :arguments => []})
      end

      it 'recognizes lambda reference invocation arguments' do
        expect(parser.phrase).to parse('full_name(:Thomas, :Ingram)').as(:invocation => {:reference => 'full_name', :arguments => [{:string => 'Thomas'}, {:string => 'Ingram'}]})
      end

      it 'recognizes operator invocation' do
        expect(parser.phrase).to parse('2 + 2').as(:invocation => {:operand => {:integer => '2'}, :operator => {:reference => '+'}, :argument => {:integer => '2'}})
      end

      it 'recognizes assignment as an operator invocation' do
        expect(parser.phrase).to parse('favorite_language = :rip').as(:invocation => {:operand => {:reference => 'favorite_language'}, :operator => {:reference => '='}, :argument => {:string => 'rip'}})
      end
    end

    context 'nested parenthesis' do
      it 'recognizes anything surrounded by parenthesis' do
        expect(parser.phrase).to parse('(0)').as(:integer => '0')
      end

      it 'recognizes anything surrounded by parenthesis with crazy nesting' do
        expected = {
          :invocation => {
            :reference => 'l',
            :arguments => [
              {
                :operator_invocation => {
                  :operand => { :integer => '1' },
                  :operator => { :reference => '+' },
                  :argument => {
                    :operator_invocation => {
                      :operand => { :integer => '2' },
                      :operator => { :reference => '-' },
                      :argument => { :integer => '3' }
                    }
                  }
                }
              }
            ]
          }
        }
        expect(parser.phrase).to parse('((((((l((1 + (((2 - 3)))))))))))').as(expected)
      end
    end

    context 'property chaining' do
      it 'recognizes chaining with properies and invocations' do
        expected = {
          :integer => '0',
          :invocation => {
            :reference => 'one', :arguments => [],
            :property => {
              :reference => 'two',
              :invocation => {:reference => 'three', :arguments => []}
            }
          }
        }
        expect(parser.phrase).to parse('0.one().two.three()').as(expected)
      end

      it 'recognizes chaining off opererators' do
        expected = {
          :operator_invocation => {
            :operand => { :integer => '1' },
            :operator => { :reference => '-' },
            :argument => { :integer => '2' },
            :invocation => {
              :reference => 'zero?',
              :parameters => []
            }
          }
        }
        expect(parser.phrase).to parse('(1 - 2).zero?()').as(expected)
      end

      it 'recognizes chaining several opererators' do
        expected = {
          :operator_invocation => {
            :operand => {
              :operator_invocation => {
                :operand => {
                  :operator_invocation => {
                    :operand => {:reference => '1'},
                    :operator => {:reference => '+'},
                    :argument => {:reference => '2'}
                  }
                },
                :operator => {:reference => '+'},
                :argument => {:reference => '3'}
              }
            },
            :operator => {:reference => '+'},
            :argument => {:reference => '4'}
          }
        }
        expect(parser.phrase).to parse('1 + 2 + 3 + 4').as(expected)
      end
    end
  end

  describe '#object' do
    context 'atomic literals' do
      it 'recognizes numbers' do
        expect(parser.numeric).to parse('42').as(:integer => '42')
        expect(parser.numeric).to parse('4.2').as(:decimal => '4.2')
        expect(parser.numeric).to parse('-3').as(:sign => '-', :integer => '3')
        expect(parser.numeric).to parse('123_456_789').as(:integer => '123_456_789')
      end

      it 'recognizes characters' do
        expect(parser.character).to parse('`9').as(:character => '9')
        expect(parser.character).to parse('`f').as(:character => 'f')
      end

      it 'recognizes strings' do
        expect(parser.string).to parse(':0').as(:string => '0')
        expect(parser.string).to parse(':one').as(:string => 'one')
        expect(parser.string).to parse('\'two\'').as(:string => 'two')
        expect(parser.string).to parse('"three"').as(:string => 'three')
        expect(parser.string).to parse(<<-RIP.split("\n").map(&:strip).join("\n")).as(:here_doc_start => 'HERE_DOC', :string => "here docs are good for multi-line strings\n", :here_doc_end => 'HERE_DOC')
                                       <<HERE_DOC
                                       here docs are good for multi-line strings
                                       HERE_DOC
                                       RIP
      end

      it 'recognizes regular expressions' do
        expect(parser.regular_expression).to parse('/hello/').as(:regex => 'hello')
      end
    end

    context 'molecular literals' do
      it 'recognizes key-value pairs' do
        expect(parser.key_value_pair).to parse('5: \'five\'').as(:key => {:integer => '5'}, :value => {:string => 'five'})
        expect(parser.key_value_pair).to parse('Exception: e').as(:key => {:reference => 'Exception'}, :value => {:reference => 'e'})
      end

      it 'recognizes ranges' do
        expect(parser.range).to parse('1..3').as(:start => {:integer => '1'}, :end => {:integer => '3'}, :exclusivity => nil)
        expect(parser.range).to parse('1...age').as(:start => {:integer => '1'}, :end => {:reference => 'age'}, :exclusivity => '.')
      end

      it 'recognizes hashes' do
        expect(parser.hash_literal).to parse('{}').as(:hash => [])
        expect(parser.hash_literal).to parse('{:name: :Thomas}').as(:hash => [{:key => {:string => 'name'}, :value => {:string => 'Thomas'}}])
        expect(parser.hash_literal).to parse(<<-RIP.strip).as(:hash => [{:key => {:string => 'age'}, :value => {:integer => '31'}}, {:key => {:string => 'name'}, :value => {:string => 'Thomas'}}])
                                             {
                                               :age: 31,
                                               :name: :Thomas
                                             }
                                             RIP
      end

      it 'recognizes lists' do
        expect(parser.list).to parse('[]').as(:list => [])
        expect(parser.list).to parse('[:Thomas]').as(:list => [{:string => 'Thomas'}])
        expect(parser.list).to parse(<<-RIP.strip).as(:list => [{:integer => '31'}, {:string => 'Thomas'}])
                                     [
                                       31,
                                       :Thomas
                                     ]
                                     RIP
      end
    end
  end
end
