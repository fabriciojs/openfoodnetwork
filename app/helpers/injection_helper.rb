require 'open_food_network/enterprise_injection_data'

module InjectionHelper
  include SerializerHelper

  def inject_enterprises(enterprises = Enterprise.activated.includes(address: :state).all)
    inject_json_ams(
      "enterprises",
      enterprises,
      Api::EnterpriseSerializer,
      enterprise_injection_data
    )
  end

  def inject_groups
    select_only = required_attributes EnterpriseGroup, Api::GroupListSerializer

    inject_json_ams(
      "groups",
      EnterpriseGroup.on_front_page.by_position.select(select_only).includes(address: :state).all,
      Api::GroupListSerializer
    )
  end

  def inject_enterprise_shopfront(enterprise)
    inject_json_ams(
      "shopfront",
      enterprise,
      Api::EnterpriseShopfrontSerializer
    )
  end

  def inject_enterprise_shopfront_list
    select_only = required_attributes Enterprise, Api::EnterpriseShopfrontListSerializer

    inject_json_ams(
      "enterprises",
      Enterprise.activated.visible.select(select_only).includes(address: :state).all,
      Api::EnterpriseShopfrontListSerializer
    )
  end

  def inject_enterprise_and_relatives
    inject_json_ams "enterprises", current_distributor.relatives_including_self.activated.includes(address: :state).all, Api::EnterpriseSerializer, enterprise_injection_data
  end

  def inject_group_enterprises
    inject_json_ams(
      "enterprises",
      @group.enterprises.activated.all,
      Api::EnterpriseSerializer,
      enterprise_injection_data
    )
  end

  def inject_current_hub
    inject_json_ams "currentHub", current_distributor, Api::EnterpriseSerializer, enterprise_injection_data
  end

  def inject_current_order
    inject_json_ams "currentOrder", current_order, Api::CurrentOrderSerializer, current_distributor: current_distributor, current_order_cycle: current_order_cycle
  end

  def inject_available_shipping_methods
    inject_json_ams "shippingMethods", available_shipping_methods,
                    Api::ShippingMethodSerializer, current_order: current_order
  end

  def inject_available_payment_methods
    inject_json_ams "paymentMethods", available_payment_methods,
                    Api::PaymentMethodSerializer, current_order: current_order
  end

  def inject_taxons
    inject_json_ams "taxons", Spree::Taxon.all, Api::TaxonSerializer
  end

  def inject_properties
    inject_json_ams "properties", Spree::Property.all, Api::PropertySerializer
  end

  def inject_currency_config
    inject_json_ams "currencyConfig", {}, Api::CurrencyConfigSerializer
  end

  def inject_spree_api_key
    render partial: "json/injection_ams", locals: { name: 'spreeApiKey', json: "'#{@spree_api_key}'" }
  end

  def inject_available_countries
    inject_json_ams "availableCountries", available_countries, Api::CountrySerializer
  end

  def inject_enterprise_attributes
    render partial: "json/injection_ams", locals: { name: 'enterpriseAttributes', json: @enterprise_attributes.to_json.to_s }
  end

  def inject_orders
    inject_json_ams "orders", @orders.all, Api::OrderSerializer
  end

  def inject_shops
    customers = spree_current_user.customers
    shops = Enterprise.where(id: @orders.pluck(:distributor_id).uniq | customers.pluck(:enterprise_id))
    inject_json_ams "shops", shops.all, Api::ShopForOrdersSerializer
  end

  def inject_saved_credit_cards
    data = spree_current_user ? spree_current_user.credit_cards.with_payment_profile.all : []

    inject_json_ams "savedCreditCards", data, Api::CreditCardSerializer
  end

  def inject_json(name, partial, opts = {})
    render partial: "json/injection", locals: { name: name, partial: partial }.merge(opts)
  end

  def inject_json_ams(name, data, serializer, opts = {})
    if data.is_a?(Array)
      opts = { each_serializer: serializer }.merge(opts)
      serializer = ActiveModel::ArraySerializer
    end

    serializer_instance = serializer.new(data, opts)
    json = serializer_instance.to_json
    render partial: "json/injection_ams", locals: { name: name, json: json }
  end

  private

  def enterprise_injection_data
    @enterprise_injection_data ||= OpenFoodNetwork::EnterpriseInjectionData.new
    { data: @enterprise_injection_data }
  end
end
