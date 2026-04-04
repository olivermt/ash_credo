defmodule AshCredo.Check.HelpersTest do
  use AshCredo.CheckCase

  alias AshCredo.Check.Helpers

  @ash_resource """
  defmodule MyApp.Post do
    use Ash.Resource, domain: MyApp.Blog

    attributes do
      uuid_primary_key :id
      attribute :title, :string, public?: true
      attribute :body, :string
      timestamps()
    end

    actions do
      defaults [:read, :destroy]

      create :create do
        primary? true
        accept [:title, :body]
      end
    end
  end
  """

  @ash_domain """
  defmodule MyApp.Blog do
    use Ash.Domain

    resources do
      resource MyApp.Post
    end
  end
  """

  @plain_module """
  defmodule MyApp.Utils do
    def hello, do: :world
  end
  """

  describe "ash_resource?/1" do
    test "returns true for Ash.Resource modules" do
      assert Helpers.ash_resource?(source_file(@ash_resource))
    end

    test "returns false for non-Ash modules" do
      refute Helpers.ash_resource?(source_file(@plain_module))
    end

    test "returns false for Ash.Domain modules" do
      refute Helpers.ash_resource?(source_file(@ash_domain))
    end
  end

  describe "ash_domain?/1" do
    test "returns true for Ash.Domain modules" do
      assert Helpers.ash_domain?(source_file(@ash_domain))
    end

    test "returns false for non-Ash modules" do
      refute Helpers.ash_domain?(source_file(@plain_module))
    end
  end

  describe "find_dsl_section/2" do
    test "finds the attributes section" do
      sf = source_file(@ash_resource)
      result = Helpers.find_dsl_section(sf, :attributes)
      assert {:attributes, _, _} = result
    end

    test "finds the actions section" do
      sf = source_file(@ash_resource)
      result = Helpers.find_dsl_section(sf, :actions)
      assert {:actions, _, _} = result
    end

    test "returns nil for missing section" do
      sf = source_file(@ash_resource)
      assert nil == Helpers.find_dsl_section(sf, :policies)
    end
  end

  describe "has_entity?/2" do
    test "detects entity in section" do
      sf = source_file(@ash_resource)
      attrs = Helpers.find_dsl_section(sf, :attributes)
      assert Helpers.has_entity?(attrs, :uuid_primary_key)
      assert Helpers.has_entity?(attrs, :timestamps)
    end

    test "returns false for missing entity" do
      sf = source_file(@ash_resource)
      attrs = Helpers.find_dsl_section(sf, :attributes)
      refute Helpers.has_entity?(attrs, :integer_primary_key)
    end

    test "returns false for nil section" do
      refute Helpers.has_entity?(nil, :anything)
    end
  end

  describe "find_entities/2" do
    test "finds all attribute entities" do
      sf = source_file(@ash_resource)
      attrs = Helpers.find_dsl_section(sf, :attributes)
      attributes = Helpers.find_entities(attrs, :attribute)
      assert length(attributes) == 2
    end

    test "returns empty list for nil section" do
      assert [] == Helpers.find_entities(nil, :attribute)
    end
  end

  describe "use_opts/2" do
    test "extracts opts from use call" do
      sf = source_file(@ash_resource)
      opts = Helpers.use_opts(sf, [:Ash, :Resource])
      assert is_list(opts)
      assert Keyword.has_key?(opts, :domain)
    end

    test "returns empty list when no opts" do
      source = """
      defmodule Foo do
        use Ash.Resource
      end
      """

      sf = source_file(source)
      assert [] == Helpers.use_opts(sf, [:Ash, :Resource])
    end
  end

  describe "section_line/1" do
    test "returns line number for a section" do
      sf = source_file(@ash_resource)
      attrs = Helpers.find_dsl_section(sf, :attributes)
      assert is_integer(Helpers.section_line(attrs))
    end

    test "returns nil for nil" do
      assert nil == Helpers.section_line(nil)
    end
  end

  describe "entity_opts/1" do
    test "extracts inline keyword opts" do
      sf = source_file(@ash_resource)
      attrs = Helpers.find_dsl_section(sf, :attributes)
      [title | _] = Helpers.find_entities(attrs, :attribute)
      opts = Helpers.entity_opts(title)
      assert Keyword.has_key?(opts, :public?)
    end

    test "returns empty list for entity without opts" do
      assert [] == Helpers.entity_opts({:timestamps, [line: 1], []})
    end

    test "excludes :do key from opts" do
      ast = {:create, [line: 1], [:create, [do: {:accept, [], [[:title]]}]]}
      refute Keyword.has_key?(Helpers.entity_opts(ast), :do)
    end
  end

  describe "entity_has_opt?/3" do
    test "detects inline opt value" do
      sf = source_file(@ash_resource)
      attrs = Helpers.find_dsl_section(sf, :attributes)
      [title | _] = Helpers.find_entities(attrs, :attribute)
      assert Helpers.entity_has_opt?(title, :public?, true)
      refute Helpers.entity_has_opt?(title, :public?, false)
    end

    test "detects opt in do block" do
      sf = source_file(@ash_resource)
      actions = Helpers.find_dsl_section(sf, :actions)
      [create] = Helpers.find_entities(actions, :create)
      assert Helpers.entity_has_opt?(create, :primary?, true)
    end
  end

  describe "entity_has_opt_key?/2" do
    test "detects inline opt key" do
      sf = source_file(@ash_resource)
      attrs = Helpers.find_dsl_section(sf, :attributes)
      [title | _] = Helpers.find_entities(attrs, :attribute)
      assert Helpers.entity_has_opt_key?(title, :public?)
      refute Helpers.entity_has_opt_key?(title, :sensitive?)
    end

    test "detects opt key in do block" do
      sf = source_file(@ash_resource)
      actions = Helpers.find_dsl_section(sf, :actions)
      [create] = Helpers.find_entities(actions, :create)
      assert Helpers.entity_has_opt_key?(create, :primary?)
    end
  end

  describe "entity_name/1" do
    test "extracts atom name from entity" do
      sf = source_file(@ash_resource)
      actions = Helpers.find_dsl_section(sf, :actions)
      [create] = Helpers.find_entities(actions, :create)
      assert :create == Helpers.entity_name(create)
    end

    test "returns nil for non-entity" do
      assert nil == Helpers.entity_name(:not_an_entity)
    end
  end

  describe "find_in_body/2" do
    test "finds call inside do block" do
      sf = source_file(@ash_resource)
      actions = Helpers.find_dsl_section(sf, :actions)
      [create] = Helpers.find_entities(actions, :create)
      assert {:accept, _, _} = Helpers.find_in_body(create, :accept)
    end

    test "returns nil when call not found" do
      sf = source_file(@ash_resource)
      actions = Helpers.find_dsl_section(sf, :actions)
      [create] = Helpers.find_entities(actions, :create)
      assert nil == Helpers.find_in_body(create, :description)
    end

    test "returns nil for non-tuple input" do
      assert nil == Helpers.find_in_body(nil, :anything)
    end
  end

  describe "section_body/1" do
    test "returns statements from section" do
      sf = source_file(@ash_resource)
      attrs = Helpers.find_dsl_section(sf, :attributes)
      body = Helpers.section_body(attrs)
      assert is_list(body)
      refute Enum.empty?(body)
    end

    test "returns empty list for nil" do
      assert [] == Helpers.section_body(nil)
    end
  end

  describe "section_has_entries?/1" do
    test "returns true for non-empty section" do
      sf = source_file(@ash_resource)
      attrs = Helpers.find_dsl_section(sf, :attributes)
      assert Helpers.section_has_entries?(attrs)
    end

    test "returns false for nil" do
      refute Helpers.section_has_entries?(nil)
    end
  end

  describe "actions_defined?/1" do
    test "returns true when explicit actions exist" do
      sf = source_file(@ash_resource)
      actions = Helpers.find_dsl_section(sf, :actions)
      assert Helpers.actions_defined?(actions)
    end

    test "returns true when defaults define actions" do
      source = """
      defmodule Foo do
        use Ash.Resource

        actions do
          defaults [:read, :destroy]
        end
      end
      """

      sf = source_file(source)
      actions = Helpers.find_dsl_section(sf, :actions)
      assert Helpers.actions_defined?(actions)
    end

    test "returns false for nil" do
      refute Helpers.actions_defined?(nil)
    end
  end

  describe "default_action_entries/1" do
    test "extracts entries from defaults call" do
      source = """
      defmodule Foo do
        use Ash.Resource

        actions do
          defaults [:read, create: :*]
        end
      end
      """

      sf = source_file(source)
      actions = Helpers.find_dsl_section(sf, :actions)
      [defaults] = Helpers.find_entities(actions, :defaults)
      entries = Helpers.default_action_entries(defaults)
      assert :read in entries
      assert {:create, :*} in entries
    end

    test "returns empty list for non-defaults" do
      assert [] == Helpers.default_action_entries(:not_defaults)
    end
  end

  describe "default_action_has_value?/3" do
    test "detects action type with specific value" do
      source = """
      defmodule Foo do
        use Ash.Resource

        actions do
          defaults [:read, create: :*]
        end
      end
      """

      sf = source_file(source)
      actions = Helpers.find_dsl_section(sf, :actions)
      [defaults] = Helpers.find_entities(actions, :defaults)
      assert Helpers.default_action_has_value?(defaults, :create, :*)
      refute Helpers.default_action_has_value?(defaults, :update, :*)
    end
  end

  describe "find_all_policy_entities/1" do
    test "finds top-level policy and bypass" do
      source = """
      defmodule Foo do
        use Ash.Resource

        policies do
          policy action_type(:read) do
            authorize_if always()
          end

          bypass action_type(:destroy) do
            authorize_if always()
          end
        end
      end
      """

      sf = source_file(source)
      policies = Helpers.find_dsl_section(sf, :policies)
      entities = Helpers.find_all_policy_entities(policies)
      assert length(entities) == 2
    end

    test "finds policies nested inside policy_group" do
      source = """
      defmodule Foo do
        use Ash.Resource

        policies do
          policy_group do
            policy action_type(:read) do
              authorize_if always()
            end
          end
        end
      end
      """

      sf = source_file(source)
      policies = Helpers.find_dsl_section(sf, :policies)
      entities = Helpers.find_all_policy_entities(policies)
      assert length(entities) == 1
    end

    test "returns empty list for nil" do
      assert [] == Helpers.find_all_policy_entities(nil)
    end
  end

  describe "entity_body/1" do
    test "extracts body statements from entity with do block" do
      sf = source_file(@ash_resource)
      actions = Helpers.find_dsl_section(sf, :actions)
      [create] = Helpers.find_entities(actions, :create)
      body = Helpers.entity_body(create)
      assert is_list(body)
      refute Enum.empty?(body)
    end

    test "returns empty list for entity without do block" do
      assert [] == Helpers.entity_body({:timestamps, [line: 1], []})
    end

    test "returns empty list for nil" do
      assert [] == Helpers.entity_body(nil)
    end
  end

  describe "find_use_line/2" do
    test "returns line number of use call" do
      sf = source_file(@ash_resource)
      line = Helpers.find_use_line(sf, [:Ash, :Resource])
      assert is_integer(line)
    end

    test "returns nil when use not found" do
      sf = source_file(@plain_module)
      assert nil == Helpers.find_use_line(sf, [:Ash, :Resource])
    end
  end

  describe "has_data_layer?/1" do
    test "returns true for non-embedded data layers" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, domain: MyApp.Blog, data_layer: AshPostgres.DataLayer
      end
      """

      assert Helpers.has_data_layer?(source_file(source))
    end

    test "returns false for embedded resources" do
      source = """
      defmodule MyApp.Post do
        use Ash.Resource, data_layer: :embedded
      end
      """

      sf = source_file(source)

      refute Helpers.has_data_layer?(sf)
      assert Helpers.embedded_resource?(sf)
    end
  end
end
