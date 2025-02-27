require 'spec_helper'
require 'open_food_network/permissions'

describe ProductImport::ProductImporter do
  include AuthenticationWorkflow

  let!(:admin) { create(:admin_user) }
  let!(:user) { create_enterprise_user }
  let!(:user2) { create_enterprise_user }
  let!(:user3) { create_enterprise_user }
  let!(:enterprise) { create(:enterprise, is_primary_producer: true, owner: user, name: "User Enterprise") }
  let!(:enterprise2) { create(:distributor_enterprise, is_primary_producer: true, owner: user2, name: "Another Enterprise") }
  let!(:enterprise3) { create(:distributor_enterprise, is_primary_producer: true, owner: user3, name: "And Another Enterprise") }
  let!(:enterprise4) { create(:enterprise, is_primary_producer: false, owner: user, name: "Non-Producer") }
  let!(:relationship) { create(:enterprise_relationship, parent: enterprise, child: enterprise2, permissions_list: [:create_variant_overrides]) }

  let!(:category) { create(:taxon, name: 'Vegetables') }
  let!(:category2) { create(:taxon, name: 'Cake') }
  let!(:category3) { create(:taxon, name: 'Meat') }
  let!(:category4) { create(:taxon, name: 'Cereal') }
  let!(:tax_category) { create(:tax_category) }
  let!(:tax_category2) { create(:tax_category) }
  let!(:shipping_category) { create(:shipping_category) }

  let!(:product) { create(:simple_product, supplier: enterprise2, name: 'Hypothetical Cake', description: nil, primary_taxon_id: category2.id) }
  let!(:variant) { create(:variant, product_id: product.id, price: '8.50', on_hand: '100', unit_value: '500', display_name: 'Preexisting Banana') }
  let!(:product2) { create(:simple_product, supplier: enterprise, on_hand: '100', name: 'Beans', unit_value: '500', primary_taxon_id: category.id, description: nil) }
  let!(:product3) { create(:simple_product, supplier: enterprise, on_hand: '100', name: 'Sprouts', unit_value: '500', primary_taxon_id: category.id) }
  let!(:product4) { create(:simple_product, supplier: enterprise, on_hand: '100', name: 'Cabbage', unit_value: '1', variant_unit_scale: nil, variant_unit: "items", variant_unit_name: "Whole", primary_taxon_id: category.id) }
  let!(:product5) { create(:simple_product, supplier: enterprise2, on_hand: '100', name: 'Lettuce', unit_value: '500', primary_taxon_id: category.id) }
  let!(:product6) { create(:simple_product, supplier: enterprise3, on_hand: '100', name: 'Beetroot', unit_value: '500', on_demand: true, variant_unit_scale: 1, variant_unit: 'weight', primary_taxon_id: category.id, description: nil) }
  let!(:product7) { create(:simple_product, supplier: enterprise3, on_hand: '100', name: 'Tomato', unit_value: '500', variant_unit_scale: 1, variant_unit: 'weight', primary_taxon_id: category.id, description: nil) }

  let!(:product8) { create(:simple_product, supplier: enterprise, on_hand: '100', name: 'Oats', description: "", unit_value: '500', variant_unit_scale: 1, variant_unit: 'weight', primary_taxon_id: category4.id) }
  let!(:product9) { create(:simple_product, supplier: enterprise, on_hand: '100', name: 'Oats', description: "", unit_value: '500', variant_unit_scale: 1, variant_unit: 'weight', primary_taxon_id: category4.id) }
  let!(:variant2) { create(:variant, product_id: product8.id, price: '4.50', on_hand: '100', unit_value: '500', display_name: 'Porridge Oats') }
  let!(:variant3) { create(:variant, product_id: product8.id, price: '5.50', on_hand: '100', unit_value: '500', display_name: 'Rolled Oats') }
  let!(:variant4) { create(:variant, product_id: product9.id, price: '6.50', on_hand: '100', unit_value: '500', display_name: 'Flaked Oats') }

  let!(:variant_override) { create(:variant_override, variant_id: product4.variants.first.id, hub: enterprise2, count_on_hand: 42) }
  let!(:variant_override2) { create(:variant_override, variant_id: product5.variants.first.id, hub: enterprise, count_on_hand: 96) }

  let(:permissions) { OpenFoodNetwork::Permissions.new(user) }

  after(:each) do
    File.delete('/tmp/test-m.csv')
  end

  describe "importing products from a spreadsheet" do
    before do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "category", "on_hand", "price", "units", "unit_type", "variant_unit_name", "on_demand", "shipping_category"]
        csv << ["Carrots", "User Enterprise", "Vegetables", "5", "3.20", "500", "g", "", "", shipping_category.name]
        csv << ["Potatoes", "User Enterprise", "Vegetables", "6", "6.50", "2", "kg", "", "", shipping_category.name]
        csv << ["Pea Soup", "User Enterprise", "Vegetables", "8", "5.50", "750", "ml", "", "0", shipping_category.name]
        csv << ["Salad", "User Enterprise", "Vegetables", "7", "4.50", "1", "", "bags", "", shipping_category.name]
        csv << ["Hot Cross Buns", "User Enterprise", "Cake", "7", "3.50", "1", "", "buns", "1", shipping_category.name]
      end
      @importer = import_data csv_data
    end

    it "returns the number of entries" do
      expect(@importer.item_count).to eq(5)
    end

    it "validates entries and returns the results as json" do
      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 5
      expect(filter('invalid', entries)).to eq 0
      expect(filter('create_product', entries)).to eq 5
      expect(filter('update_product', entries)).to eq 0
    end

    it "saves the results and returns info on updated products" do
      @importer.save_entries

      expect(@importer.products_created_count).to eq 5
      expect(@importer.updated_ids).to be_a(Array)
      expect(@importer.updated_ids.count).to eq 5

      carrots = Spree::Product.find_by_name('Carrots')
      expect(carrots.supplier).to eq enterprise
      expect(carrots.on_hand).to eq 5
      expect(carrots.price).to eq 3.20
      expect(carrots.unit_value).to eq 500
      expect(carrots.variant_unit).to eq 'weight'
      expect(carrots.variant_unit_scale).to eq 1
      expect(carrots.on_demand).to_not eq true
      expect(carrots.variants.first.import_date).to be_within(1.minute).of Time.zone.now

      potatoes = Spree::Product.find_by_name('Potatoes')
      expect(potatoes.supplier).to eq enterprise
      expect(potatoes.on_hand).to eq 6
      expect(potatoes.price).to eq 6.50
      expect(potatoes.unit_value).to eq 2000
      expect(potatoes.variant_unit).to eq 'weight'
      expect(potatoes.variant_unit_scale).to eq 1000
      expect(potatoes.on_demand).to_not eq true
      expect(potatoes.variants.first.import_date).to be_within(1.minute).of Time.zone.now

      pea_soup = Spree::Product.find_by_name('Pea Soup')
      expect(pea_soup.supplier).to eq enterprise
      expect(pea_soup.on_hand).to eq 8
      expect(pea_soup.price).to eq 5.50
      expect(pea_soup.unit_value).to eq 0.75
      expect(pea_soup.variant_unit).to eq 'volume'
      expect(pea_soup.variant_unit_scale).to eq 0.001
      expect(pea_soup.on_demand).to_not eq true
      expect(pea_soup.variants.first.import_date).to be_within(1.minute).of Time.zone.now

      salad = Spree::Product.find_by_name('Salad')
      expect(salad.supplier).to eq enterprise
      expect(salad.on_hand).to eq 7
      expect(salad.price).to eq 4.50
      expect(salad.unit_value).to eq 1
      expect(salad.variant_unit).to eq 'items'
      expect(salad.variant_unit_scale).to eq nil
      expect(salad.on_demand).to_not eq true
      expect(salad.variants.first.import_date).to be_within(1.minute).of Time.zone.now

      buns = Spree::Product.find_by_name('Hot Cross Buns')
      expect(buns.supplier).to eq enterprise
      expect(buns.on_hand).to eq 7
      expect(buns.price).to eq 3.50
      expect(buns.unit_value).to eq 1
      expect(buns.variant_unit).to eq 'items'
      expect(buns.variant_unit_scale).to eq nil
      expect(buns.on_demand).to eq true
      expect(buns.variants.first.import_date).to be_within(1.minute).of Time.zone.now
    end
  end

  describe "when uploading a spreadsheet with some invalid entries" do
    before do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "category", "on_hand", "price", "units", "unit_type", "shipping_category"]
        csv << ["Good Carrots", "User Enterprise", "Vegetables", "5", "3.20", "500", "g", shipping_category.name]
        csv << ["Bad Potatoes", "", "Vegetables", "6", "6.50", "1", "", shipping_category.name]
      end
      @importer = import_data csv_data
    end

    it "validates entries" do
      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 1
      expect(filter('invalid', entries)).to eq 1
      expect(filter('create_product', entries)).to eq 1
      expect(filter('update_product', entries)).to eq 0
    end

    it "allows saving of the valid entries" do
      @importer.save_entries

      expect(@importer.products_created_count).to eq 1
      expect(@importer.updated_ids).to be_a(Array)
      expect(@importer.updated_ids.count).to eq 1

      carrots = Spree::Product.find_by_name('Good Carrots')
      expect(carrots.supplier).to eq enterprise
      expect(carrots.on_hand).to eq 5
      expect(carrots.price).to eq 3.20
      expect(carrots.variants.first.import_date).to be_within(1.minute).of Time.zone.now

      expect(Spree::Product.find_by_name('Bad Potatoes')).to eq nil
    end
  end

  describe "when shipping category is missing" do
    before do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "category", "on_hand", "price", "units", "unit_type", "variant_unit_name", "on_demand", "shipping_category"]
        csv << ["Shipping Test", "User Enterprise", "Vegetables", "5", "3.20", "500", "g", "", nil, nil]
      end
      @importer = import_data csv_data
    end

    it "raises an error" do
      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(entries['2']['errors']['shipping_category']).to eq "Shipping_category can't be blank"
    end
  end

  describe "when enterprises are not valid" do
    before do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "category", "on_hand", "price", "units", "unit_type"]
        csv << ["Product 1", "Non-existent Enterprise", "Vegetables", "5", "5.50", "500", "g"]
        csv << ["Product 2", "Non-Producer", "Vegetables", "5", "5.50", "500", "g"]
      end
      @importer = import_data csv_data
    end

    it "adds enterprise errors" do
      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(entries['2']['errors']['producer']).to include "not found in database"
      expect(entries['3']['errors']['producer']).to include "not enabled as a producer"
    end
  end

  describe "adding new variants to existing products and updating exiting products" do
    before do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "category", "on_hand", "price", "units", "unit_type", "display_name", "shipping_category"]
        csv << ["Hypothetical Cake", "Another Enterprise", "Cake", "5", "5.50", "500", "g", "Preexisting Banana", shipping_category.name]
        csv << ["Hypothetical Cake", "Another Enterprise", "Cake", "6", "3.50", "500", "g", "Emergent Coffee", shipping_category.name]
      end
      @importer = import_data csv_data
    end

    it "validates entries" do
      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 2
      expect(filter('invalid', entries)).to eq 0
      expect(filter('create_product', entries)).to eq 1
      expect(filter('update_product', entries)).to eq 1
    end

    it "saves and updates" do
      @importer.save_entries

      expect(@importer.products_created_count).to eq 1
      expect(@importer.products_updated_count).to eq 1
      expect(@importer.updated_ids).to be_a(Array)
      expect(@importer.updated_ids.count).to eq 2

      added_coffee = Spree::Variant.find_by_display_name('Emergent Coffee')
      expect(added_coffee.product.name).to eq 'Hypothetical Cake'
      expect(added_coffee.price).to eq 3.50
      expect(added_coffee.on_hand).to eq 6
      expect(added_coffee.import_date).to be_within(1.minute).of Time.zone.now

      updated_banana = Spree::Variant.find_by_display_name('Preexisting Banana')
      expect(updated_banana.product.name).to eq 'Hypothetical Cake'
      expect(updated_banana.price).to eq 5.50
      expect(updated_banana.on_hand).to eq 5
      expect(updated_banana.import_date).to be_within(1.minute).of Time.zone.now
    end
  end

  describe "adding new product and sub-variant at the same time" do
    before do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "category", "on_hand", "price", "units", "unit_type", "display_name", "shipping_category"]
        csv << ["Potatoes", "User Enterprise", "Vegetables", "5", "3.50", "500", "g", "Small Bag", shipping_category.name]
        csv << ["Chives", "User Enterprise", "Vegetables", "6", "4.50", "500", "g", "Small Bag", shipping_category.name]
        csv << ["Potatoes", "User Enterprise", "Vegetables", "6", "5.50", "2", "kg", "Big Bag", shipping_category.name]
        csv << ["Potatoes", "User Enterprise", "Vegetables", "6", "22.00", "10000", "g", "Small Sack", shipping_category.name]
        csv << ["Potatoes", "User Enterprise", "Vegetables", "6", "60.00", "30000", "", "Big Sack", shipping_category.name]
      end
      @importer = import_data csv_data
    end

    it "validates entries" do
      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 3
      expect(filter('invalid', entries)).to eq 2
      expect(filter('create_product', entries)).to eq 3
    end

    it "saves and updates" do
      @importer.save_entries

      expect(@importer.products_created_count).to eq 3
      expect(@importer.updated_ids).to be_a(Array)
      expect(@importer.updated_ids.count).to eq 3

      small_bag = Spree::Variant.find_by_display_name('Small Bag')
      expect(small_bag.product.name).to eq 'Potatoes'
      expect(small_bag.price).to eq 3.50
      expect(small_bag.on_hand).to eq 5

      big_bag = Spree::Variant.find_by_display_name("Big Bag")
      expect(big_bag).to be_blank

      small_sack = Spree::Variant.find_by_display_name("Small Sack")
      expect(small_sack.product.name).to eq "Potatoes"
      expect(small_sack.price).to eq 22.00
      expect(small_sack.on_hand).to eq 6
      expect(small_sack.product.id).to eq small_bag.product.id

      big_sack = Spree::Variant.find_by_display_name("Big Sack")
      expect(big_sack).to be_blank
    end
  end

  describe "updating various fields" do
    before do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "category", "on_hand", "price", "units", "unit_type", "on_demand", "sku", "shipping_category"]
        csv << ["Beetroot", "And Another Enterprise", "Vegetables", "5", "3.50", "500", "g", "0", nil, shipping_category.name]
        csv << ["Tomato", "And Another Enterprise", "Vegetables", "6", "5.50", "500", "g", "1", "TOMS", shipping_category.name]
      end
      @importer = import_data csv_data
    end

    it "validates entries" do
      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 2
      expect(filter('invalid', entries)).to eq 0
      expect(filter('create_product', entries)).to eq 0
      expect(filter('update_product', entries)).to eq 2
    end

    it "saves and updates" do
      @importer.save_entries

      expect(@importer.products_created_count).to eq 0
      expect(@importer.products_updated_count).to eq 2
      expect(@importer.updated_ids).to be_a(Array)
      expect(@importer.updated_ids.count).to eq 2

      beetroot = Spree::Product.find_by_name('Beetroot').variants.first
      expect(beetroot.price).to eq 3.50
      expect(beetroot.on_demand).to_not eq true

      tomato = Spree::Product.find_by_name('Tomato').variants.first
      expect(tomato.price).to eq 5.50
      expect(tomato.on_demand).to eq true
    end
  end

  describe "updating non-updatable fields on existing products" do
    before do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "category", "on_hand", "price", "units", "unit_type"]
        csv << ["Beetroot", "And Another Enterprise", "Meat", "5", "3.50", "500", "g"]
        csv << ["Tomato", "And Another Enterprise", "Vegetables", "6", "5.50", "500", "Kg"]
      end
      @importer = import_data csv_data
    end

    it "does not allow updating" do
      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 0
      expect(filter('invalid', entries)).to eq 2

      @importer.entries.each do |entry|
        expect(entry.errors.messages.values).to include [I18n.t('admin.product_import.model.not_updatable')]
      end
    end
  end

  describe "when more than one product of the same name already exists with multiple variants each" do
    before do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "category", "description", "on_hand", "price", "units", "unit_type", "display_name", "shipping_category"]
        csv << ["Oats", "User Enterprise", "Cereal", "", "50", "3.50", "500", "g", "Rolled Oats", shipping_category.name]   # Update
        csv << ["Oats", "User Enterprise", "Cereal", "", "80", "3.75", "500", "g", "Flaked Oats", shipping_category.name]   # Update
        csv << ["Oats", "User Enterprise", "Cereal", "", "60", "5.50", "500", "g", "Magic Oats", shipping_category.name]    # Add
        csv << ["Oats", "User Enterprise", "Cereal", "", "70", "8.50", "500", "g", "French Oats", shipping_category.name]   # Add
        csv << ["Oats", "User Enterprise", "Cereal", "", "70", "8.50", "500", "g", "Scottish Oats", shipping_category.name] # Add
      end
      @importer = import_data csv_data
    end

    it "validates entries" do
      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 5
      expect(filter('invalid', entries)).to eq 0
      expect(filter('create_product', entries)).to eq 3
      expect(filter('update_product', entries)).to eq 2
      expect(filter('create_inventory', entries)).to eq 0
      expect(filter('update_inventory', entries)).to eq 0
    end

    it "saves and updates" do
      @importer.save_entries

      expect(@importer.products_created_count).to eq 3
      expect(@importer.products_updated_count).to eq 2
      expect(@importer.inventory_created_count).to eq 0
      expect(@importer.inventory_updated_count).to eq 0
      expect(@importer.updated_ids.count).to eq 5
    end
  end

  describe "when importer processes create and update across multiple stages" do
    before do
      @csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "category", "on_hand", "price", "units", "unit_type", "display_name", "shipping_category"]
        csv << ["Bag of Oats", "User Enterprise", "Cereal", "60", "5.50", "500", "g", "Magic Oats", shipping_category.name]     # Add
        csv << ["Bag of Oats", "User Enterprise", "Cereal", "70", "8.50", "500", "g", "French Oats", shipping_category.name]    # Add
        csv << ["Bag of Oats", "User Enterprise", "Cereal", "80", "9.50", "500", "g", "Organic Oats", shipping_category.name]   # Add
        csv << ["Bag of Oats", "User Enterprise", "Cereal", "90", "7.50", "500", "g", "Scottish Oats", shipping_category.name]  # Add
        csv << ["Bag of Oats", "User Enterprise", "Cereal", "30", "6.50", "500", "g", "Breakfast Oats", shipping_category.name] # Add
      end
    end

    it "processes the validation in stages" do
      # Using settings of start: 1, end: 3 to simulate import over multiple stages
      @importer = import_data @csv_data, start: 1, end: 3

      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 3
      expect(filter('invalid', entries)).to eq 0
      expect(filter('create_product', entries)).to eq 3
      expect(filter('update_product', entries)).to eq 0
      expect(filter('create_inventory', entries)).to eq 0
      expect(filter('update_inventory', entries)).to eq 0

      @importer = import_data @csv_data, start: 4, end: 6

      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 2
      expect(filter('invalid', entries)).to eq 0
      expect(filter('create_product', entries)).to eq 2
      expect(filter('update_product', entries)).to eq 0
      expect(filter('create_inventory', entries)).to eq 0
      expect(filter('update_inventory', entries)).to eq 0
    end

    it "processes saving in stages" do
      @importer = import_data @csv_data, start: 1, end: 3
      @importer.save_entries

      expect(@importer.products_created_count).to eq 3
      expect(@importer.products_updated_count).to eq 0
      expect(@importer.inventory_created_count).to eq 0
      expect(@importer.inventory_updated_count).to eq 0
      expect(@importer.updated_ids.count).to eq 3

      @importer = import_data @csv_data, start: 4, end: 6
      @importer.save_entries

      expect(@importer.products_created_count).to eq 2
      expect(@importer.products_updated_count).to eq 0
      expect(@importer.inventory_created_count).to eq 0
      expect(@importer.inventory_updated_count).to eq 0
      expect(@importer.updated_ids.count).to eq 2

      products = Spree::Product.find_all_by_name('Bag of Oats')

      expect(products.count).to eq 1
      expect(products.first.variants.count).to eq 5
    end
  end

  describe "importing items into inventory" do
    describe "creating and updating inventory" do
      before do
        csv_data = CSV.generate do |csv|
          csv << ["name", "distributor", "producer", "on_hand", "price", "units", "unit_type", "variant_unit_name"]
          csv << ["Beans", "Another Enterprise", "User Enterprise", "5", "3.20", "500", "g", ""]
          csv << ["Sprouts", "Another Enterprise", "User Enterprise", "6", "6.50", "500", "g", ""]
          csv << ["Cabbage", "Another Enterprise", "User Enterprise", "2001", "1.50", "1", "", "Whole"]
        end
        @importer = import_data csv_data, import_into: 'inventories'
      end

      it "validates entries" do
        @importer.validate_entries
        entries = JSON.parse(@importer.entries_json)

        expect(filter('valid', entries)).to eq 3
        expect(filter('invalid', entries)).to eq 0
        expect(filter('create_inventory', entries)).to eq 2
        expect(filter('update_inventory', entries)).to eq 1
      end

      it "saves and updates inventory" do
        @importer.save_entries

        expect(@importer.inventory_created_count).to eq 2
        expect(@importer.inventory_updated_count).to eq 1
        expect(@importer.updated_ids).to be_a(Array)
        expect(@importer.updated_ids.count).to eq 3

        beans_override = VariantOverride.where(variant_id: product2.variants.first.id, hub_id: enterprise2.id).first
        sprouts_override = VariantOverride.where(variant_id: product3.variants.first.id, hub_id: enterprise2.id).first
        cabbage_override = VariantOverride.where(variant_id: product4.variants.first.id, hub_id: enterprise2.id).first

        expect(Float(beans_override.price)).to eq 3.20
        expect(beans_override.count_on_hand).to eq 5

        expect(Float(sprouts_override.price)).to eq 6.50
        expect(sprouts_override.count_on_hand).to eq 6

        expect(Float(cabbage_override.price)).to eq 1.50
        expect(cabbage_override.count_on_hand).to eq 2001
      end
    end

    describe "updating existing inventory referenced by display_name" do
      before do
        csv_data = CSV.generate do |csv|
          csv << ["name", "display_name", "distributor", "producer", "on_hand", "price", "units"]
          csv << ["Oats", "Porridge Oats", "Another Enterprise", "User Enterprise", "900", "", "500"]
        end
        @importer = import_data csv_data, import_into: 'inventories'
      end

      it "updates inventory item correctly" do
        @importer.save_entries

        expect(@importer.inventory_created_count).to eq 1

        override = VariantOverride.where(variant_id: variant2.id, hub_id: enterprise2.id).first
        visible = InventoryItem.where(variant_id: variant2.id, enterprise_id: enterprise2.id).first.visible

        expect(override.count_on_hand).to eq 900
        expect(visible).to be_truthy
      end
    end

    describe "updating existing item that was set to hidden in inventory" do
      before do
        InventoryItem.create(variant_id: product4.variants.first.id, enterprise_id: enterprise2.id, visible: false)

        csv_data = CSV.generate do |csv|
          csv << ["name", "distributor", "producer", "on_hand", "price", "units", "variant_unit_name"]
          csv << ["Cabbage", "Another Enterprise", "User Enterprise", "900", "", "1", "Whole"]
        end
        @importer = import_data csv_data, import_into: 'inventories'
      end

      it "sets the item to visible in inventory when the item is updated" do
        @importer.save_entries

        expect(@importer.inventory_updated_count).to eq 1

        override = VariantOverride.where(variant_id: product4.variants.first.id, hub_id: enterprise2.id).first
        visible = InventoryItem.where(variant_id: product4.variants.first.id, enterprise_id: enterprise2.id).first.visible

        expect(override.count_on_hand).to eq 900
        expect(visible).to be_truthy
      end
    end
  end

  describe "handling enterprise permissions" do
    it "only allows product import into enterprises the user is permitted to manage" do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "category", "on_hand", "price", "units", "unit_type", "shipping_category"]
        csv << ["My Carrots", "User Enterprise", "Vegetables", "5", "3.20", "500", "g", shipping_category.name]
        csv << ["Your Potatoes", "Another Enterprise", "Vegetables", "6", "6.50", "1", "kg", shipping_category.name]
      end
      @importer = import_data csv_data, import_user: user

      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 1
      expect(filter('invalid', entries)).to eq 1
      expect(filter('create_product', entries)).to eq 1

      @importer.save_entries

      expect(@importer.products_created_count).to eq 1
      expect(@importer.updated_ids).to be_a(Array)
      expect(@importer.updated_ids.count).to eq 1

      expect(Spree::Product.find_by_name('My Carrots')).to be_a Spree::Product
      expect(Spree::Product.find_by_name('Your Potatoes')).to eq nil
    end

    it "allows creating inventories for producers that a user's hub has permission for" do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "distributor", "on_hand", "price", "units", "unit_type"]
        csv << ["Beans", "User Enterprise", "Another Enterprise", "777", "3.20", "500", "g"]
      end
      @importer = import_data csv_data, import_into: 'inventories'

      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 1
      expect(filter('invalid', entries)).to eq 0
      expect(filter('create_inventory', entries)).to eq 1

      @importer.save_entries

      expect(@importer.inventory_created_count).to eq 1
      expect(@importer.updated_ids).to be_a(Array)
      expect(@importer.updated_ids.count).to eq 1

      beans = VariantOverride.where(variant_id: product2.variants.first.id, hub_id: enterprise2.id).first
      expect(beans.count_on_hand).to eq 777
    end

    it "does not allow creating inventories for producers that a user's hubs don't have permission for" do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "on_hand", "price", "units", "unit_type"]
        csv << ["Beans", "User Enterprise", "5", "3.20", "500", "g"]
        csv << ["Sprouts", "User Enterprise", "6", "6.50", "500", "g"]
      end
      @importer = import_data csv_data, import_into: 'inventories'

      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 0
      expect(filter('invalid', entries)).to eq 2
      expect(filter('create_inventory', entries)).to eq 0

      @importer.save_entries

      expect(@importer.inventory_created_count).to eq 0
      expect(@importer.updated_ids).to be_a(Array)
      expect(@importer.updated_ids.count).to eq 0
    end
  end

  describe "applying settings and defaults on import" do
    it "can reset all products for an enterprise that are not present in the uploaded file to zero stock" do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "category", "on_hand", "price", "units", "unit_type", "shipping_category"]
        csv << ["Carrots", "User Enterprise", "Vegetables", "5", "3.20", "500", "g", shipping_category.name]
        csv << ["Beans", "User Enterprise", "Vegetables", "6", "6.50", "500", "g", shipping_category.name]
      end
      @importer = import_data csv_data, reset_all_absent: true

      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 2
      expect(filter('invalid', entries)).to eq 0
      expect(filter('create_product', entries)).to eq 1
      expect(filter('update_product', entries)).to eq 1

      @importer.save_entries

      expect(@importer.products_created_count).to eq 1
      expect(@importer.products_updated_count).to eq 1
      expect(@importer.updated_ids).to be_a(Array)
      expect(@importer.updated_ids.count).to eq 2

      updated_ids = @importer.updated_ids

      @importer = import_data csv_data, reset_all_absent: true, updated_ids: updated_ids, enterprises_to_reset: [enterprise.id]
      @importer.reset_absent(updated_ids)

      expect(@importer.products_reset_count).to eq 7

      expect(Spree::Product.find_by_name('Carrots').on_hand).to eq 5    # Present in file, added
      expect(Spree::Product.find_by_name('Beans').on_hand).to eq 6      # Present in file, updated
      expect(Spree::Product.find_by_name('Sprouts').on_hand).to eq 0    # In enterprise, not in file
      expect(Spree::Product.find_by_name('Cabbage').on_hand).to eq 0    # In enterprise, not in file
      expect(Spree::Product.find_by_name('Lettuce').on_hand).to eq 100  # In different enterprise; unchanged
    end

    it "can reset all inventory items for an enterprise that are not present in the uploaded file to zero stock" do
      csv_data = CSV.generate do |csv|
        csv << ["name", "distributor", "producer", "on_hand", "price", "units", "unit_type"]
        csv << ["Beans", "Another Enterprise", "User Enterprise", "6", "3.20", "500", "g"]
        csv << ["Sprouts", "Another Enterprise", "User Enterprise", "7", "6.50", "500", "g"]
      end
      @importer = import_data csv_data, import_into: 'inventories', reset_all_absent: true

      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 2
      expect(filter('invalid', entries)).to eq 0
      expect(filter('create_inventory', entries)).to eq 2

      @importer.save_entries

      expect(@importer.inventory_created_count).to eq 2
      expect(@importer.updated_ids).to be_a(Array)
      expect(@importer.updated_ids.count).to eq 2

      updated_ids = @importer.updated_ids

      @importer = import_data csv_data, import_into: 'inventories', reset_all_absent: true, updated_ids: updated_ids, enterprises_to_reset: [enterprise2.id]
      @importer.reset_absent(updated_ids)

      # expect(@importer.products_reset_count).to eq 1

      beans = VariantOverride.where(variant_id: product2.variants.first.id, hub_id: enterprise2.id).first
      sprouts = VariantOverride.where(variant_id: product3.variants.first.id, hub_id: enterprise2.id).first
      cabbage = VariantOverride.where(variant_id: product4.variants.first.id, hub_id: enterprise2.id).first
      lettuce = VariantOverride.where(variant_id: product5.variants.first.id, hub_id: enterprise.id).first

      expect(beans.count_on_hand).to eq 6      # Present in file, created
      expect(sprouts.count_on_hand).to eq 7    # Present in file, created
      expect(cabbage.count_on_hand).to eq 0    # In enterprise, not in file (reset)
      expect(lettuce.count_on_hand).to eq 96   # In different enterprise; unchanged
    end

    it "can overwrite fields with selected defaults when importing to product list" do
      csv_data = CSV.generate do |csv|
        csv << ["name", "producer", "category", "on_hand", "price", "units", "unit_type", "tax_category_id", "available_on", "shipping_category"]
        csv << ["Carrots", "User Enterprise", "Vegetables", "5", "3.20", "500", "g", tax_category.id, "", shipping_category.name]
        csv << ["Potatoes", "User Enterprise", "Vegetables", "6", "6.50", "1", "kg", "", "", shipping_category.name]
      end
      settings = { enterprise.id.to_s => {
        'import_into' => 'product_list',
        'defaults' => {
          'on_hand' => {
            'active' => true,
            'mode' => 'overwrite_all',
            'value' => '9000'
          },
          'tax_category_id' => {
            'active' => true,
            'mode' => 'overwrite_empty',
            'value' => tax_category2.id
          },
          'shipping_category_id' => {
            'active' => true,
            'mode' => 'overwrite_all',
            'value' => shipping_category.id
          },
          'available_on' => {
            'active' => true,
            'mode' => 'overwrite_all',
            'value' => '2020-01-01'
          }
        }
      } }

      @importer = import_data csv_data, settings: settings

      @importer.validate_entries
      entries = JSON.parse(@importer.entries_json)

      expect(filter('valid', entries)).to eq 2
      expect(filter('invalid', entries)).to eq 0
      expect(filter('create_product', entries)).to eq 2

      @importer.save_entries

      expect(@importer.products_created_count).to eq 2
      expect(@importer.updated_ids).to be_a(Array)
      expect(@importer.updated_ids.count).to eq 2

      carrots = Spree::Product.find_by_name('Carrots')
      expect(carrots.on_hand).to eq 9000
      expect(carrots.tax_category_id).to eq tax_category.id
      expect(carrots.shipping_category_id).to eq shipping_category.id
      expect(carrots.available_on).to be_within(1.day).of(Time.zone.local(2020, 1, 1))

      potatoes = Spree::Product.find_by_name('Potatoes')
      expect(potatoes.on_hand).to eq 9000
      expect(potatoes.tax_category_id).to eq tax_category2.id
      expect(potatoes.shipping_category_id).to eq shipping_category.id
      expect(potatoes.available_on).to be_within(1.day).of(Time.zone.local(2020, 1, 1))
    end
  end
end

private

def import_data(csv_data, args = {})
  import_user = args[:import_user] || admin
  import_into = args[:import_into] || 'product_list'
  start_row = args[:start] || 1
  end_row = args[:end] || 100
  reset_all_absent = args[:reset_all_absent] || false
  updated_ids = args[:updated_ids] || nil
  enterprises_to_reset = args[:enterprises_to_reset] || nil
  settings = args[:settings] || { 'import_into' => import_into, 'reset_all_absent' => reset_all_absent }

  File.write('/tmp/test-m.csv', csv_data)
  @file ||= File.new('/tmp/test-m.csv')
  ProductImport::ProductImporter.new(@file,
                                     import_user,
                                     start: start_row,
                                     end: end_row,
                                     updated_ids: updated_ids,
                                     enterprises_to_reset: enterprises_to_reset,
                                     settings: settings)
end

def filter(type, entries)
  valid_count = 0
  entries.each do |_line_number, entry|
    validates_as = entry['validates_as']

    valid_count += 1 if type == 'valid' && (validates_as != '')
    valid_count += 1 if type == 'invalid' && (validates_as == '')
    valid_count += 1 if type == 'create_product' && (validates_as == 'new_product' || validates_as == 'new_variant')
    valid_count += 1 if type == 'update_product' && validates_as == 'existing_variant'
    valid_count += 1 if type == 'create_inventory' && validates_as == 'new_inventory_item'
    valid_count += 1 if type == 'update_inventory' && validates_as == 'existing_inventory_item'
  end
  valid_count
end
