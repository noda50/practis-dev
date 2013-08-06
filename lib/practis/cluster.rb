#!/usr/bin/env ruby
# -*- coding: utf-8 -*-

require 'json'

require 'practis'

module Practis

  #=== Node information to construct cluster tree.
  #
  #Primary key is id variable.
  class ClusterNode

    include Practis

    # Node type in NODE_TYPE_MANAGER or NODE_TYPE_CONTROLLER or
    # NODE_TYPE_EXECUTOR
    attr_accessor :node_type
    # Primary key identifier. This should be allocated by Manager.
    attr_accessor  :id
    # IP address
    attr_accessor :address
    # Parent node identifier.
    attr_accessor :parent
    # Children nodes identifiers.
    attr_accessor :children
    # Only executor has how may parallel execution can.
    attr_accessor :parallel
    # The number of queueing parameter set
    attr_accessor :queueing
    # The number of executing parameter set
    attr_accessor :executing
    #
    attr_accessor :keepalive

    def initialize(node_type, address, id, parallel = nil)
      raise RuntimeError, "Invalid node type! #{node_type.to_s}" \
        unless NODE_TYPES.include?(node_type)
      @node_type = chk_arg(String, node_type)
      @id = chk_arg(Integer, id)
      @address = chk_arg(String, address)
      @children = chk_arg(Array, [])
      @parallel = chk_arg(Integer, parallel, true)
      @parent = nil
      @parallel = 1 unless @parallel.nil? || parallel > 1
      @queueing = 0
      @executing = 0
      @keepalive = DEFAULT_KEEPALIVE
    end

    #=== Matcher.
    #
    #Check the keytype variable equals with ket or not.
    #
    #keytype :: node_type or id or address.
    #key :: The value of keytype variable.
    #
    #returned_value :: Boolean value whehter match or not.
    def match(keytype, key)
      case keytype
      when :node_type
        @node_type == key
      when :id
        @id == key
      when :address
        @address == key
      else
        false
      end
    end

    #=== Convert to string.
    #
    #String format is as follow:
    #
    # 'node_type: %10s, id:%7d, address: %15s'
    #
    #returned_value :: A string including node_type, id and address.
    def to_s
      parallel = @parallel.to_s
      case
      when @parent.nil? then parent = nil.to_s
      when @parent.kind_of?(Integer) then parent = @parent.to_s
      else parent = @parent.id.to_s
      end
      children = []
      @children.each do |child|
        case child.class.name
        when "Integer" then children.push(child)
        when "String" then children.push(child.to_i)
        else children.push(child.id)
        end
      end
      #children_string = array_to_string(children)
      children_string = children.join(",")
      sprintf("node_type: %s, address: %s, id: %d, parallel: %s, parent: %s, " +
              "children: %s, queueing: %d, executing: %d, keepalive: %d",
              @node_type, @address, @id, parallel.to_s, parent, children_string,
              queueing, executing, keepalive)
    end

    #=== Convert tot Json.
    #
    #Json format is as follows:
    # [{:node_type => "manager", :id => 1, :address => "192.168.1.1"}]
    #
    #returned_value :: Json object including node_type, id and address.
    def to_json
      parent = nil
      parent = @parent.id unless @parent.nil?
      children = []
      @children.each {|child| children.push(child.id) }
      JSON.generate({:node_type => @node_type, :address => @address, :id => @id,
                     :parallel => @parallel, :parent => parent,
                     :children => children})
    end

    def self.json_to_object(json)
      hash = JSON.parse(json, :symbolize_names => true)
      # variables = [:node_type, :id, :address, :parallel, :parent,
        # :children]
      # variables.each do |val|
      [:node_type, :id, :address, :parallel, :parent, :children].each do |val|
        unless hash.key?(val)
          error("json does not contain #{val}")
          nil
        end
      end
      node = ClusterNode.new(hash[:node_type], hash[:address], hash[:id],
                             hash[:parallel])
      node.parent = hash[:parent].nil? ? nil : hash[:parent].to_i
      hash[:children].each {|child| node.children.push(child) }
      return node
    end
  end

  #=== Overview of Practis clusters.
  #
  #Manager handles the overview of the Practis clusters.
  class ClusterTree

    include Practis

    # Root ClusterNode of the cluster tree.
    attr_accessor :root
    attr_accessor :id_pool

    def initialize
      @root = nil
      @id_pool = []
    end

    #=== Allocate new id in this cluster tree.
    #ID must be unique, this method allocate a new ID for any cluster nodes.
    #id :: if you want to specify a static id, use this arg.
    #returned_value :: an allocated new id.
    def allocate_new_id(id = nil)
      (error("ID pool is already full!"); nil) \
        if @id_pool.length >= Practis::MAX_NODES
      new_id = -1
      if id.nil?
        while true
          new_id = rand(Practis::MAX_NODES).to_i
          (@id_pool.push(new_id); break) unless @id_pool.include?(new_id)
        end
      else
        new_id = id
        (error("specified ID already exist!"); nil) if @id_pool.include?(new_id)
        @id_pool.push(new_id)
      end
      new_id
    end

    #=== reate method.
    def create(parent, node_type, address, id = nil, parallel = nil)
      if (id = allocate_new_id(id)).nil?
        error("ID is nil")
        return nil
      end
      node = nil
      begin
        node = ClusterNode.new(node_type, address, id, parallel)
      rescue ArgumentError => e
        error(e.message)
        e.backtrace.each { |b| error(b) }
        error("cannot creat a node with type: #{node_type}, address: " +
              "#{address}, id: #{id}, parallel: #{parallel}")
        @id_pool.delete(id)
        return nil
      end
      node.parent = parent
      if parent.nil? && @root.nil?
        @root = node
        return node
      end
      search(parent, :id, parent.id, l = [])
      if l.length != 1
        error("cannot find match parent id")
        nil
      else
        parent.children.push(node)
        node.parent = parent
        node
      end
    end

    #=== Read method.
    #Wrapper of search method.
    def read(keytype, key, root=@root)
      search(root, keytype, key, l = [])
      l
    end

    #=== Search method.
    #
    #Search matching ClusterNode.
    #
    #root :: A node to start searching.
    #keytype :: variable type from node_type or id or address.
    #key :: Used by ClusterNode.match.
    #l :: Matched values are stored in l.
    def search(root, keytype, key, l)
      l.push(root) if root.match(keytype, key)
      root.children.each {|node| search(node, keytype, key, l) } \
        if root.children.length > 0
    end

    #=== Update method.
    #
    #Update matching ndoes variables.
    #
    #keytype :: Used by ClusterNode.match.
    #key :: Used by ClusterNode.match.
    #update_keytpe :: Updated value type.
    #update_value :: Updated value.
    def update(keytype, key, update_keytype, update_value)
      read(keytype, key).each do |node|
        case update_keytype
        when :node_type then node.node_type = update_value
        when :id then node.id = update_value
        when :address then node.address = update_value
        when :parallel then node.parallel = update_value
        when :queueing then node.queueing = update_value
        when :executing then node.executing = update_value
        when :keepalive then node.keepalive = update_value
        else warn("specified update key does not exist: #{update_keytype}")
        end
      end
    end

    #=== Delete method.
    def delete(keytype, key)
      read(keytype, key).each do |node|
        node.children.each do |child|
          child.parent = node.parent
          node.parent.children.push(child) if node.parent != nil
        end
        if node.parent != nil
          node.parent.children.delete(node)
        else
          # This node is Manager. Basically this method is not permitted!
          raise RuntimeError
        end
      end
    end

    #=== Get the depth of the node.
    #Wrapper for get_depth method.
    #
    #node :: The node to know the depth.
    #returned_value :: depth. If could not get the depth, return -1.
    def depth(node)
      get_depth(node, @root, 0)
    end

    #=== Get the depth of the node in this cluster tree.
    #
    #node :: The node to know the depth.
    #root :: To recursive call.
    #count :: Current depth.
    #returned_value :: depth. If could not get the depth, return -1.
    def get_depth(node, root, count)
      count if node == root
      if root.children.length > 0
        count + 1 if root.children.include?(node)
        root.children.each do |child|
          if (val = get_depth(node, child, count + 1)) > 0
            return val
          end
        end
        0   # cannot find
      end
      0   # cannot find
    end

    #=== Get all nodes in this tree from the root.
    #
    #root :: Start to get the nodes.
    #returned_value :: A list including all ndoes.
    def get_nodes(root = @root)
      recursive_get_nodes(root, l = [])   # nodes are stored in this list.
      l
    end

    #=== Get nodes and recursively call each child.
    #node :: Get nodes from.
    #l :: Nodes stored in this list.
    def recursive_get_nodes(node, l)
      l.push(node)
      node.children.each {|child| recursive_get_nodes(child, l) } \
        if node.children.length > 0
    end

    #=== Convert this tree to String.
    #node :: Generate the tree from the node.
    #returned_value :: Tree string.
    def to_s(node = @root)
      node = @root if node.nil?
      str = ''
      #depth_spaces = '  ' * depth(node)
      str << '  ' * depth(node)
      #str += sprintf("%s%s\n", depth_spaces, node.to_s)
      str << "#{node.to_s}\n"
      node.children.each {|child| str << to_s(child) } \
        if node.children.length > 0
      str
    end

    #=== Convert this tree to JSON object.
    #node :: Start node to convert to JSON.
    #returned_value :: A JSON object of the tree.
    def to_json(node = @root)
      JSON.generate(recursive_to_json(node))
    end

    #=== Convert this tree to JSON object to recursive call..
    def recursive_to_json(node=@root)
      children = []
      node.children.each {|child| children.push(recursive_to_json(child)) }
      jnode = JSON.parse(node.to_json, :symbolize_names => true)
      jnode.delete("children")
      jnode[:children] = children
      jnode
    end

    def self.json_to_object(json)
      root = Practis::ClusterTree.recursive_json_to_object(JSON.parse(json,
          :symbolize_names => true))
      root.parent = nil
      tree = Practis::ClusterTree.new
      tree.root = root
      return tree
    end

    def self.recursive_json_to_object(hash)
      node = ClusterNode.new(hash[:node_type], hash[:address], hash[:id],
                             hash[:parallel])
      hash[:children].each do |child|
        child_node = Practis::ClusterTree.recursive_json_to_object(child)
        child_node.parent = node
        node.children.push(child_node)
      end
      return node
    end

    #=== Create JSON of partial tree.
    #The partial tree consists of the node, the parent of the node, and the
    #children of the node.
    def get_partial_tree(id)
      node = read(:id, id)[0]
      partial_tree = PartialTree.new
      partial_tree.mynode = JSON.parse(node.to_json, :symbolize_names => true)
      node.parent.nil? ?  partial_tree.parent = nil :
        partial_tree.parent = JSON.parse(node.parent.to_json,
                                         :symbolize_names => true)
      node.children.each {|child| partial_tree.children.push(
          JSON.parse(child.to_json, :symbolize_names => true)) }
      return partial_tree
    end
  end

  class PartialTree

    include Practis

    attr_accessor :parent, :mynode, :children

    def initialize(mynode = nil)
      @parent = nil
      @mynode = mynode
      @children = []
    end

    #=== Convert this tree to String.
    #node :: Generate the tree from the node.
    #returned_value :: Tree string.
    def to_s
      str = ''
      str << "#{parent}\n" unless parent.nil?
      str << "  #{mynode}\n"
      children.each {|child| str << "    #{to_s(child)}" } \
        if children.length > 0
      str
    end

    def to_json
      JSON.generate({:parent => @parent, :mynode => @mynode,
                     :children => @children})
    end

    def self.json_to_object(json)
      hash = JSON.parse(json, :symbolize_names => true)
      partial_tree = Practis::PartialTree.new
      partial_tree.parent = hash[:parent]
      partial_tree.mynode = hash[:mynode]
      hash[:children].each {|child| partial_tree.children.push(child) }
      return partial_tree
    end
  end
end
