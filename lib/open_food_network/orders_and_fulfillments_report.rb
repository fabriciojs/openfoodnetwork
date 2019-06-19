require "open_food_network/reports/line_items"

include Spree::ReportsHelper

module OpenFoodNetwork
  class OrdersAndFulfillmentsReport
    attr_reader :params
    def initialize(user, params = {}, render_table = false)
      @params = params
      @user = user
      @render_table = render_table
    end

    def header
      case params[:report_type]

      when "order_cycle_supplier_totals"
        [I18n.t(:report_header_producer), I18n.t(:report_header_product), I18n.t(:report_header_variant), I18n.t(:report_header_amount),
         I18n.t(:report_header_total_units), I18n.t(:report_header_curr_cost_per_unit), I18n.t(:report_header_total_cost),
         I18n.t(:report_header_status), I18n.t(:report_header_incoming_transport)]
      when "order_cycle_supplier_totals_by_distributor"
        [I18n.t(:report_header_producer), I18n.t(:report_header_product), I18n.t(:report_header_variant), I18n.t(:report_header_to_hub),
         I18n.t(:report_header_amount), I18n.t(:report_header_curr_cost_per_unit), I18n.t(:report_header_total_cost),
         I18n.t(:report_header_shipping_method)]
      when "order_cycle_distributor_totals_by_supplier"
        [I18n.t(:report_header_hub), I18n.t(:report_header_producer), I18n.t(:report_header_product), I18n.t(:report_header_variant),
         I18n.t(:report_header_amount), I18n.t(:report_header_curr_cost_per_unit), I18n.t(:report_header_total_cost),
         I18n.t(:report_header_total_shipping_cost), I18n.t(:report_header_shipping_method)]
      when "order_cycle_customer_totals"
        [I18n.t(:report_header_hub), I18n.t(:report_header_customer), I18n.t(:report_header_email), I18n.t(:report_header_phone),
         I18n.t(:report_header_producer), I18n.t(:report_header_product), I18n.t(:report_header_variant), I18n.t(:report_header_amount),
         I18n.t(:report_header_item_price, currency: currency_symbol),
         I18n.t(:report_header_item_fees_price, currency: currency_symbol),
         I18n.t(:report_header_admin_handling_fees, currency: currency_symbol),
         I18n.t(:report_header_ship_price, currency: currency_symbol),
         I18n.t(:report_header_pay_fee_price, currency: currency_symbol),
         I18n.t(:report_header_total_price, currency: currency_symbol),
         I18n.t(:report_header_paid), I18n.t(:report_header_shipping), I18n.t(:report_header_delivery),
         I18n.t(:report_header_ship_street), I18n.t(:report_header_ship_street_2), I18n.t(:report_header_ship_city), I18n.t(:report_header_ship_postcode), I18n.t(:report_header_ship_state),
         I18n.t(:report_header_comments), I18n.t(:report_header_sku),
         I18n.t(:report_header_order_cycle), I18n.t(:report_header_payment_method), I18n.t(:report_header_customer_code), I18n.t(:report_header_tags),
         I18n.t(:report_header_billing_street), I18n.t(:report_header_billing_street_2), I18n.t(:report_header_billing_city), I18n.t(:report_header_billing_postcode), I18n.t(:report_header_billing_state),]
      else
        [I18n.t(:report_header_producer), I18n.t(:report_header_product), I18n.t(:report_header_variant),
         I18n.t(:report_header_amount), I18n.t(:report_header_curr_cost_per_unit), I18n.t(:report_header_total_cost),
         I18n.t(:report_header_status), I18n.t(:report_header_incoming_transport)]
      end
    end

    def search
      Reports::LineItems.search_orders(permissions, params)
    end

    def table_items
      return [] unless @render_table
      Reports::LineItems.list(permissions, params)
    end

    def rules
      case params[:report_type]
      when "order_cycle_supplier_totals"
        [
          {
            group_by: proc { |line_item| Spree::Variant.unscoped.find(line_item.variant_id).product.supplier },
            sort_by: proc { |supplier| supplier.name }
          },
          {
            group_by: proc { |line_item| Spree::Variant.unscoped.find(line_item.variant_id).product },
            sort_by: proc { |product| product.name }
          },
          {
            group_by: proc { |line_item| Spree::Variant.unscoped.find(line_item.variant_id).full_name },
            sort_by: proc { |full_name| full_name }
          }
        ]
      when "order_cycle_supplier_totals_by_distributor"
        [
          {
            group_by: proc { |line_item| Spree::Variant.unscoped.find(line_item.variant_id).product.supplier },
            sort_by: proc { |supplier| supplier.name }
          },
          {
            group_by: proc { |line_item| Spree::Variant.unscoped.find(line_item.variant_id).product },
            sort_by: proc { |product| product.name }
          },
          {
            group_by: proc { |line_item| Spree::Variant.unscoped.find(line_item.variant_id).full_name },
            sort_by: proc { |full_name| full_name },
            summary_columns: [
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| I18n.t('admin.reports.total') },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |line_items| line_items.sum(&:amount) },
              proc { |_line_items| "" }
            ]
          },
         {
           group_by: proc { |line_item| line_item.order.distributor },
           sort_by: proc { |distributor| distributor.name }
         }
        ]
      when "order_cycle_distributor_totals_by_supplier"
        [
          {
            group_by: proc { |line_item| line_item.order.distributor },
            sort_by: proc { |distributor| distributor.name },
            summary_columns: [
              proc { |_line_items| "" },
              proc { |_line_items| I18n.t('admin.reports.total') },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |line_items| line_items.sum(&:amount) },
              proc { |line_items| line_items.map(&:order).uniq.sum(&:ship_total) },
              proc { |_line_items| "" }
            ]
          },
          {
            group_by: proc { |line_item| Spree::Variant.unscoped.find(line_item.variant_id).product.supplier },
            sort_by: proc { |supplier| supplier.name }
          },
          {
            group_by: proc { |line_item| Spree::Variant.unscoped.find(line_item.variant_id).product },
            sort_by: proc { |product| product.name }
          },
          {
            group_by: proc { |line_item| Spree::Variant.unscoped.find(line_item.variant_id).full_name },
            sort_by: proc { |full_name| full_name }
          }
        ]
      when "order_cycle_customer_totals"
        [
          {
            group_by: proc { |line_item| line_item.order.distributor },
            sort_by: proc { |distributor| distributor.name }
          },
          {
            group_by: proc { |line_item| line_item.order },
            sort_by: proc { |order| order.bill_address.full_name_reverse },
            summary_columns: [
              proc { |line_items| line_items.first.order.distributor.name },
              proc { |line_items| line_items.first.order.bill_address.full_name },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| I18n.t('admin.reports.total') },
              proc { |_line_items| "" },

              proc { |_line_items| "" },
              proc { |line_items| line_items.sum(&:amount) },
              proc { |line_items| line_items.sum(&:amount_with_adjustments) },
              proc { |line_items| line_items.first.order.admin_and_handling_total },
              proc { |line_items| line_items.first.order.ship_total },
              proc { |line_items| line_items.first.order.payment_fee },
              proc { |line_items| line_items.first.order.total },
              proc { |line_items| line_items.first.order.paid? ? I18n.t(:yes) : I18n.t(:no) },

              proc { |_line_items| "" },
              proc { |_line_items| "" },

              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| "" },

              proc { |line_items| line_items.first.order.special_instructions },
              proc { |_line_items| "" },

              proc { |line_items| line_items.first.order.order_cycle.andand.name },
              proc { |line_items|
                line_items.first.order.payments.first.andand.payment_method.andand.name
              },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| "" },
              proc { |_line_items| "" }
            ]
          },
          {
            group_by: proc { |line_item| Spree::Variant.unscoped.find(line_item.variant_id).product },
            sort_by: proc { |product| product.name }
          },
          {
            group_by: proc { |line_item| Spree::Variant.unscoped.find(line_item.variant_id) },
            sort_by: proc { |variant| variant.full_name }
          },
          {
            group_by: proc { |line_item| Spree::Variant.unscoped.find(line_item.variant_id).full_name },
            sort_by: proc { |full_name| full_name }
          }
        ]
      else
        [
          {
            group_by: proc { |line_item| line_item.product.supplier },
            sort_by: proc { |supplier| supplier.name }
          },
          {
            group_by: proc { |line_item| line_item.product },
            sort_by: proc { |product| product.name }
          },
          {
            group_by: proc { |line_item| line_item.full_name },
            sort_by: proc { |full_name| full_name }
          }
        ]
      end
    end

    def columns
      case params[:report_type]
      when "order_cycle_supplier_totals"
        [proc { |line_items| Spree::Variant.unscoped.find(line_items.first.variant_id).product.supplier.name },
         proc { |line_items| Spree::Variant.unscoped.find(line_items.first.variant_id).product.name },
         proc { |line_items| Spree::Variant.unscoped.find(line_items.first.variant_id).full_name },
         proc { |line_items| line_items.sum(&:quantity) },
         proc { |line_items| total_units(line_items) },
         proc { |line_items| line_items.first.price },
         proc { |line_items| line_items.sum(&:amount) },
         proc { |_line_items| "" },
         proc { |_line_items| I18n.t(:report_header_incoming_transport) }]
      when "order_cycle_supplier_totals_by_distributor"
        [proc { |line_items| Spree::Variant.unscoped.find(line_items.first.variant_id).product.supplier.name },
         proc { |line_items| Spree::Variant.unscoped.find(line_items.first.variant_id).product.name },
         proc { |line_items| Spree::Variant.unscoped.find(line_items.first.variant_id).full_name },
         proc { |line_items| line_items.first.order.distributor.name },
         proc { |line_items| line_items.sum(&:quantity) },
         proc { |line_items| line_items.first.price },
         proc { |line_items| line_items.sum(&:amount) },
         proc { |_line_items| I18n.t(:report_header_shipping_method) }]
      when "order_cycle_distributor_totals_by_supplier"
        [proc { |line_items| line_items.first.order.distributor.name },
         proc { |line_items| Spree::Variant.unscoped.find(line_items.first.variant_id).product.supplier.name },
         proc { |line_items| Spree::Variant.unscoped.find(line_items.first.variant_id).product.name },
         proc { |line_items| Spree::Variant.unscoped.find(line_items.first.variant_id).full_name },
         proc { |line_items| line_items.sum(&:quantity) },
         proc { |line_items| line_items.first.price },
         proc { |line_items| line_items.sum(&:amount) },
         proc { |_line_items| "" },
         proc { |_line_items| I18n.t(:report_header_shipping_method) }]
      when "order_cycle_customer_totals"
        rsa = proc { |line_items| line_items.first.order.shipping_method.andand.delivery? }
        [
          proc { |line_items| line_items.first.order.distributor.name },
          proc { |line_items| line_items.first.order.bill_address.firstname + " " + line_items.first.order.bill_address.lastname },
          proc { |line_items| line_items.first.order.email },
          proc { |line_items| line_items.first.order.bill_address.phone },
          proc { |line_items| Spree::Variant.unscoped.find(line_items.first.variant_id).product.supplier.name },
          proc { |line_items| Spree::Variant.unscoped.find(line_items.first.variant_id).product.name },
          proc { |line_items| Spree::Variant.unscoped.find(line_items.first.variant_id).full_name },

          proc { |line_items| line_items.sum(&:quantity) },
          proc { |line_items| line_items.sum(&:amount) },
          proc { |line_items| line_items.sum(&:amount_with_adjustments) },
          proc { |_line_items| "" },
          proc { |_line_items| "" },
          proc { |_line_items| "" },
          proc { |_line_items| "" },
          proc { |line_items| line_items.all? { |li| li.order.paid? } ? I18n.t(:yes) : I18n.t(:no) },

          proc { |line_items| line_items.first.order.shipping_method.andand.name },
          proc { |line_items| rsa.call(line_items) ? I18n.t(:yes) : I18n.t(:no) },

          proc { |line_items| line_items.first.order.ship_address.andand.address1 if rsa.call(line_items) },
          proc { |line_items| line_items.first.order.ship_address.andand.address2 if rsa.call(line_items) },
          proc { |line_items| line_items.first.order.ship_address.andand.city if rsa.call(line_items) },
          proc { |line_items| line_items.first.order.ship_address.andand.zipcode if rsa.call(line_items) },
          proc { |line_items| line_items.first.order.ship_address.andand.state if rsa.call(line_items) },

          proc { |_line_items| "" },
          proc { |line_items| Spree::Variant.unscoped.find(line_items.first.variant_id).sku },

          proc { |line_items| line_items.first.order.order_cycle.andand.name },
          proc { |line_items| line_items.first.order.payments.first.andand.payment_method.andand.name },
          proc { |line_items| line_items.first.order.user.andand.customer_of(line_items.first.order.distributor).andand.code },
          proc { |line_items| line_items.first.order.user.andand.customer_of(line_items.first.order.distributor).andand.tags.andand.join(', ') },

          proc { |line_items| line_items.first.order.bill_address.andand.address1 },
          proc { |line_items| line_items.first.order.bill_address.andand.address2 },
          proc { |line_items| line_items.first.order.bill_address.andand.city },
          proc { |line_items| line_items.first.order.bill_address.andand.zipcode },
          proc { |line_items| line_items.first.order.bill_address.andand.state }
        ]
      else
        [proc { |line_items| line_items.first.product.supplier.name },
         proc { |line_items| line_items.first.product.name },
         proc { |line_items| line_items.first.full_name },
         proc { |line_items| line_items.sum(&:quantity) },
         proc { |line_items| line_items.first.price },
         proc { |line_items| line_items.sum { |li| li.quantity * li.price } },
         proc { |_line_items| "" },
         proc { |_line_items| I18n.t(:report_header_incoming_transport) }]
      end
    end

    private

    def permissions
      return @permissions unless @permissions.nil?
      @permissions = OpenFoodNetwork::Permissions.new(@user)
    end

    def total_units(line_items)
      return " " if line_items.map{ |li| li.unit_value.nil? }.any?

      total_units = line_items.sum do |li|
        product = Spree::Variant.unscoped.find(li.variant_id).product
        scale_factor = ( product.variant_unit == 'weight' ? 1000 : 1 )
        li.quantity * li.unit_value / scale_factor
      end
      total_units.round(3)
    end
  end
end
