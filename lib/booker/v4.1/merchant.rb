module Booker
  module V41
    class Merchant < Booker::Client
      include ::Booker::RequestHelper

      V41_PREFIX = '/v4.1/merchant'
      V41_LOCATION_PREFIX = "#{V41_PREFIX}/location"
      V41_APPOINTMENTS_PREFIX = "#{V41_PREFIX}/appointments"
      API_METHODS = {
        appointments: "#{V41_APPOINTMENTS_PREFIX}".freeze,
        appointments_partial: "#{V41_APPOINTMENTS_PREFIX}/partial".freeze,
        appointment_confirm: "#{V41_PREFIX}/appointment/confirm".freeze,
        customers: "#{V41_PREFIX}/customers".freeze,
        create_special: "#{V41_PREFIX}/special".freeze,
        employees: "#{V41_PREFIX}/employees".freeze,
        treatments: "#{V41_PREFIX}/treatments".freeze,
        create_order: "#{V41_PREFIX}/order".freeze,
        add_product_to_order: "#{V41_PREFIX}/order/add_product".freeze,
        find_products: "#{V41_PREFIX}/order/find_products".freeze,
      }.freeze

      def online_booking_settings(location_id:)
        path = "#{V41_LOCATION_PREFIX}/#{location_id}/online_booking_settings"
        response = get path, build_params
        Booker::V4::Models::OnlineBookingSettings.from_hash(response['OnlineBookingSettings'])
      end

      def location_feature_settings(location_id:)
        response = get "#{V41_LOCATION_PREFIX}/#{location_id}/feature_settings", build_params
        Booker::V4::Models::FeatureSettings.from_hash response['FeatureSettings']
      end

      def location_day_schedules(location_id:, params: {})
        # Booker requires fromDate and toDate for JSON API, but does not use them when getDefaultDaySchedule is true
        # So datetime used for these fields does not matter
        random_datetime = Booker::V4::Models::Model.time_to_booker_datetime(Time.now)

        additional_params = {getDefaultDaySchedule: true, fromDate: random_datetime, toDate: random_datetime}
        response = get("#{V41_LOCATION_PREFIX}/#{location_id}/schedule", build_params(additional_params, params))
        response['LocationDaySchedules'].map { |sched| Booker::V4::Models::LocationDaySchedule.from_hash(sched) }
      end

      def update_location_notification_settings(location_id:, send_appointment_reminders:)
        params = build_params({NotificationSettings: { SendAppointmentReminders: send_appointment_reminders } })
        put "#{V41_LOCATION_PREFIX}/#{location_id}/notification_settings", params
      end

      def confirm_appointment(appointment_id:)
        put API_METHODS[:appointment_confirm], build_params(ID: appointment_id), Booker::V4::Models::Appointment
      end

      def appointments_partial(location_id:, start_date:, end_date:, fetch_all: true, params: {})
        additional_params = {
          LocationID: location_id,
          FromStartDate: start_date.to_date,
          ToStartDate: end_date.to_date
        }

        paginated_request(
          method: :post,
          path: API_METHODS[:appointments_partial],
          params: build_params(additional_params, params, true),
          model: Booker::V4::Models::Appointment,
          fetch_all: fetch_all
        )
      end

      def employees(location_id:, fetch_all: true, params: {})
        paginated_request(
          method: :post,
          path: API_METHODS[:employees],
          params: build_params({LocationID: location_id}, params, true),
          model: Booker::V4::Models::Employee,
          fetch_all: fetch_all
        )
      end

      def treatments(location_id:, fetch_all: true, params: {})
        paginated_request(
          method: :post,
          path: API_METHODS[:treatments],
          params: build_params({ LocationID: location_id }, params, true),
          model: Booker::V4::Models::Treatment,
          fetch_all: fetch_all
        )
      end

      def location(id:)
        response = get("#{V41_LOCATION_PREFIX}/#{id}", build_params)
        Booker::V4::Models::Location.from_hash(response)
      end

      def appointments(location_id:, start_date:, end_date:, fetch_all: true, params: {})
        additional_params = {
          LocationID: location_id,
          FromStartDate: start_date.to_date,
          ToStartDate: end_date.to_date
        }

        paginated_request(
          method: :post,
          path: API_METHODS[:appointments],
          params: build_params(additional_params, params, true),
          model: Booker::V4::Models::Appointment,
          fetch_all: fetch_all
        )
      end

      def customers(location_id:, fetch_all: true, params: {})
        additional_params = {
          FilterByExactLocationID: true,
          LocationID: location_id,
          CustomerRecordType: 1,
        }

        paginated_request(
          method: :post,
          path: API_METHODS[:customers],
          params: build_params(additional_params, params, true),
          model: Booker::V4::Models::Customer,
          fetch_all: fetch_all
        )
      end

      def customer(id:, params: {}, model: Booker::V4::Models::Customer)
        additional_params = {
          LoadUnpaidAppointments: false,
          includeFieldValues: false
        }
        get("#{V41_PREFIX}/customer/#{id}", build_params(additional_params, params), model)
      end

      def update_customer(id:, update_params: {})
        # get a raw json response because we need to send all fields back with modifications
        customer_response = customer(id: id, model: nil)

        if customer_response.present? && customer = customer_response["Customer"]
          # extract the minimum required fields to send back
          customer["Customer"] = extract_default_customer_fields(customer["Customer"])
          customer["Customer"].merge!(update_params)
          customer["LocationID"] = self.location_id
          put("#{V41_PREFIX}/customer/#{id}", build_params(customer))
        end

      end

      def extract_default_customer_fields(customer_attributes)
        customer_attributes.slice("Email", "FirstName", "LastName", "HomePhone", "WorkPhone", "CellPhone")
      end

      def create_special(location_id:, start_date:, end_date:, coupon_code:, name:, params: {})
        post(API_METHODS[:create_special], build_params({
          LocationID: location_id,
          ApplicableStartDate: start_date.in_time_zone,
          ApplicableEndDate: end_date.in_time_zone,
          CouponCode: coupon_code,
          Name: name
        }, params))
      end

      ################################################################
      ################################################################
      ################################################################

      # CreateOrder
      def create_order(params: {})
        post(API_METHODS[:create_order], build_params(params))
      end

      # AddPaymentToOrder -- Cash Only
      def add_cash_payment_to_order(order_id:,amount:,params:{})
        post("#{V41_PREFIX}/order/#{order_id}/add_payment", build_params({
          'PaymentItem' => {
            "CustomPaymentMethodID" => 4, # Cash
            "Method" => {
              "ID" => 4,
              "Name" => 'Cash',
            },
            "Amount" => {
              "Amount" => amount
            },
          }
        }, params))
      end

      def place_order(order_id:, params: {})
        post "#{V41_PREFIX}/order/#{order_id}/place_order", build_params({
        }, params)
      end

      def add_product_to_order order_id:, product_variant_id:, qty:, params: {}
        put(API_METHODS[:add_product_to_order], build_params({
          'OrderID' => order_id,
          'ProductVariantID' => product_variant_id,
          'Quantity' => qty,
        }, params))
      end

      def override_order_item_price order_id:, order_item_id:, price:, params: {}
        put("#{V41_PREFIX}/order/#{order_id}/override_price", build_params({
          'OrderItemID'      => order_item_id,
          # "OverrideReasonID": 0,
          "Price": {
            "Amount": price,
            # "CurrencyCode": "string"
          },
          # "ExcludeCustomerObject": true,
          # "ExcludeApplicableSpecials": true,
          # "ID": 0,
          # "ReturnPartialOrderObject": true
        }, params))
      end

      def find_products params: {}
        post(API_METHODS[:find_products], build_params(params))
      end

      def get_order order_id:, params: {}
        get("#{V41_PREFIX}/order/#{order_id}", build_params({
          'returnPartialObjectOrder'  => false,
          'excludeCustomerObject'     => false,
          'excludeApplicableSpecials' => true,
      }, params))
      end

      def find_orders(location_id:, params: {})
        post("#{V41_PREFIX}/orders", build_params({
          LocationID: location_id
	}, params))
      end

      def get_quantity_in_stock( product_variant_ids:, params: {})
        put("#{V41_PREFIX}/order/quantity_in_stock", build_params({
          "ProductVariantIDs": product_variant_ids
        }, params))
      end

      def create_login params
	post("#{V41_PREFIX}/user", build_params(params))
      end

      def add_customer_to_order order_id:, customer:, params: {}
        post("#{V41_PREFIX}/order/#{order_id}/add_customer", build_params({
          "Customer": customer
        }, params))
      end

    end
  end
end
