require_relative './helper'
# module that is used for formatting numbers using metrics
class CoreApi
  include Helper
  # Returns the display_type from the params , otherwise nil
  #
  # @return [String, nil] Returns the display_type  from the params , otherwise nil
  def display_type
    @params.fetch('type', nil)
  end

  # Method that checks if we need to display the total downloads
  #
  # @return [Boolean] Returns true if we need to display the total downloads
  def display_total
    display_type.present? && display_type == 'total'
  end

  # Returns the connection options used for connecting to API's
  #
  # @return [Hash] Returns the connection options used for connecting to API's
  def em_connection_options
    {
      connect_timeout: 5,        # default connection setup timeout
      inactivity_timeout: 10,    # default connection inactivity (post-setup) timeout
      ssl: {
        cipher_list: 'ALL',
        verify_peer: false,
        ssl_version: 'TLSv1'
      },
      head: {
        'ACCEPT' => '*/*',
        'Connection' => 'keep-alive'
      }
    }
  end

  # Returns the request options used for connecting to API's
  #
  # @return [Hash] Returns the request options used for connecting to API's
  def em_request_options
    {
      redirects: 5,              # follow 3XX redirects up to depth 5
      keepalive: true,           # enable keep-alive (don't send Connection:close header)
      head: {
        'ACCEPT' => '*/*'
      }
    }
  end

  # instantiates an eventmachine http request object that will be used to make the htpp request
  # @see EventMachine::HttpRequest#initialize
  #
  # @param [String] url The URL that will be used in the HTTP request
  # @return [EventMachine::HttpRequest] Returns an http request object
  def em_request(url, method)
    EventMachine::HttpRequest.new(url, em_connection_options).send(method, em_request_options)
  end

  # This method is used to reqister a error callback to a HTTP request object
  # @see #callback_error
  # @param [EventMachine::HttpRequest] http The HTTP object that will be used for reqisteringt the error callback
  # @return [void]
  def register_error_callback(http)
    http.errback { |error| callback_error(error) }
  end

  # Callback that is used before returning the response the the instance
  #
  # @param [String] response The response that will be dispatched to the instance class that made the request
  # @return [String] Returns the response
  def callback_before_success(response)
    response
  end

  # Dispatches the response either to the final callback or to the block that will use the response
  # and then call the callback
  #
  # @param [String] res The response string that will be dispatched
  # @param [Lambda] callback The callback that is used to dispatch further the response
  # @param [Proc] block The block that is used for parsing response and then calling the callback
  # @return [void]
  def dispatch_http_response(res, callback, &block)
    res.blank? ? callback.call(res) : block.call(res)
  end

  # Method that is used to register a success callback to a http object
  # @see #callback_before_success
  # @see #dispatch_http_response
  #
  # @param [EventMachine::HttpRequest] http The HTTP object that will be used for registering the success callback
  # @param [Lambda] callback The callback that will be called if the response is blank
  # @param [Proc] block If the response is not blank, the block will receive the response
  # @return [void]
  def register_success_callback(http, callback, &block)
    http.callback do
      res = callback_before_success(http.response)
      dispatch_http_response(res, callback, &block)
    end
  end

  # Method that fetch the data from a URL and registers the error and success callback to the HTTP object
  # @see #em_request
  # @see #register_error_callback
  # @see #register_success_callback
  #
  # @param [url] url The URL that is used to fetch data from
  # @param [Lambda] callback The callback that will be called if the response is blank
  # @param [Proc] block If the response is not blank, the block will receive the response
  # @return [void]
  def fetch_data(url, callback = -> {}, &block)
    http = em_request(url, 'get')
    register_error_callback(http)
    register_success_callback(http, callback, &block)
  end

  # Method that is used to react when an error happens in a HTTP request
  # and prints out an error message
  #
  # @param [Object] error The error that was raised by the HTTP request
  # @return [void]
  def callback_error(error)
    logger.debug "Error during fetching data  : #{error.inspect}"
  end

  # Method that fetch the data from a URL using parallel requests
  # @see #callback_before_success
  # @see #dispatch_http_response
  #
  # @param [Array<String>] urls The urls used to fetch data from in parallel
  # @param [Lambda] callback The callback that will be called if the response is blank
  # @param [Proc] block If the response is not blank, the block will receive the response
  # @return [void]
  def fetch_typhoeus_data(url, callback = -> {}, &block)
    hydra = http_hydra
    request = Typhoeus::Request.new(url, followlocation: true, ssl_verifypeer: false, ssl_verifyhost: 0)
    register_callbacks(request, callback, &block)
    hydra.queue(request)
    hydra.run
  end

  # Method that is used to register a success callback to a http object
  # @see #callback_before_success
  # @see #dispatch_http_response
  #
  # @param [EventMachine::HttpRequest] http The HTTP object that will be used for registering the success callback
  # @param [Lambda] callback The callback that will be called if the response is blank
  # @param [Proc] block If the response is not blank, the block will receive the response
  # @return [void]
  def register_callbacks(http, callback, &block)
    http.on_complete do |response|
      if response.success?
        res = callback_before_success(http.response.body)
        dispatch_http_response(res, callback, &block)
      elsif response.timed_out?
        # aw hell no
        callback_error('Got a time out')
      elsif response.code == 0
        # Could not get an http response, something's wrong.
        callback_error(response.return_message)
      else
        # Received a non-successful http response.
        callback_error('HTTP request failed: ' + response.code.to_s)
      end
    end
  end
end
