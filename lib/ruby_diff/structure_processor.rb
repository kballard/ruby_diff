class CodeObject
  attr_reader :name
  attr_reader :parent
  attr_reader :children
  attr_reader :sexp
  
  def initialize(name, parent=nil, sexp=Sexp.new)
    @name = name
    @parent = parent
    @sexp = sexp.deep_clone
    @children = []
    if parent
      parent.children << self
    end
  end
  
  def signature
    self.name
  end
  
  def child_signatures
    h = {}
    self.children.each{|c| h[c.signature] = c}
    h
  end
  
  def to_s
    signature
  end
  
  def ==(other)
    return false unless other.class == self.class
    (other.signature == self.signature) and (other.sexp == self.sexp)
  end
end

class ModuleCode < CodeObject
  def signature
    parent_signature = self.parent ? self.parent.signature : nil
    [parent_signature,self.name].compact.join('::')
  end
end

class ClassCode < ModuleCode
end

class MethodCode < CodeObject
  def initialize(name, parent, instance, sexp)
    super(name, parent, sexp)
    @instance = instance
  end
  
  def signature
    parent_signature = self.parent ? self.parent.signature : ""
    [parent_signature,self.name].join( @instance ? '#' : ".")
  end
end

# Meta method support
class MetaCode < CodeObject
  def initialize(name, parent, label, sexp=s() )
    super(name, parent, sexp)
    @label = label
  end
  
  def signature
    parent_signature = self.parent ? self.parent.signature : ""
    "#{parent_signature} {#{@label} #{self.name}}"
  end
end

class AccessorHandler  
  def initialize(label)
    @label = label
  end
  
  def meta_codes(args_sexp, scope)
    meta_codes = []
    args_sexp.sexp_body.each do |arg| 
      if name = name_for_arg(arg)
        meta_codes << MetaCode.new(name, scope, @label)
      end
    end
    meta_codes
  end
  
  def name_for_arg(name_sexp)
    identifier = name_sexp.to_a
    case identifier.first
      when :lit then identifier.last
      when :str then identifier.last.to_sym
      else nil
    end
  end
end

# StructureProcessor is a SexpProcessor which will generate a logical
# model of the ruby code.  It can be fooled by metaprogramming and method
# redefinition, but in most cases should be fairly accurate.
class StructureProcessor < SexpProcessor
  attr_reader   :name
  attr_accessor :code_objects
  attr_accessor :root_objects
  
  attr_accessor :scope_stack
  attr_reader   :meta_methods
  
  def initialize(name='')
    super()
    @name = name
    self.strict = false
    self.auto_shift_type = true
    
    @instance_scope = true
    @code_objects = {}
    @root_objects = {}
    @scope_stack = []
    @meta_methods = {
      :attr_accessor => AccessorHandler.new("accessor"),
      :attr_writer   => AccessorHandler.new("writer"),
      :attr_reader   => AccessorHandler.new("reader")
    }
  end
  
  def process_class(exp)
    name = exp.shift
    super_class = exp.shift
    body = exp.shift
    
    record ClassCode.new(name, self.scope, body) do
      s(:class, name, process(super_class), process(body))
    end
  end
  
  def process_module(exp)
    name = exp.shift
    body = exp.shift
    
    record ModuleCode.new(name, self.scope, body) do
      s(:class, name, process(body))
    end
  end
  
  def process_defn(exp)
    name = exp.shift
    body = process exp.shift
    
    record MethodCode.new(name, self.scope, @instance_scope, body) do
      s(:defn, name, body)
    end
  end
  
  def process_defs(exp)
    exp_scope = process exp.shift
    name = exp.shift
    body = process exp.shift
    
    record MethodCode.new(name, self.scope, false, body) do
      s(:defs, exp_scope, name, body)
    end
  end
  
  def process_sclass(exp)
    @instance_scope = false
    exp_scope = process exp.shift
    body = process exp.shift
    @instance_scope = true
    
    s(:sclass, exp_scope, body)
  end
  
  def process_fcall(exp)
    name = exp.shift
    args = process exp.shift

    if meta_handler = @meta_methods[name]
      meta_codes = meta_handler.meta_codes(args, self.scope)
      meta_codes.each{|m| record(m)}
    end
    
    return s(:fcall, name, args)
  end
  
  def diff(other_processor)
    method_diff = CodeComparison.new(self.root_objects, other_processor.root_objects).changes
  end
  
  protected
  def record obj
    signature = obj.signature
    if !self.code_objects[signature]
      self.code_objects[signature] = obj
      self.root_objects[signature] = obj if obj.parent == nil
    end
    
    self.scope_stack << self.code_objects[signature]
    result = yield if block_given?
    self.scope_stack.pop
    result
  end
  
  def scope
    self.scope_stack.last
  end
  
end
