defmodule Bamboo.MandrillAdapter do
  @default_base_uri "https://mandrillapp.com/"
  @send_message_path "api/1.0/messages/send.json"

  defmodule ApiError do
    defexception [:message]

    def exception(%{params: params, response: response}) do
      message = """
      There was a problem sending the email through the Mandrill API.

      Here is the response:

      #{inspect response}


      Here are the params we sent:

      #{inspect Poison.decode!(params)}
      """
      %ApiError{message: message}
    end
  end

  def deliver(email, config) do
    api_key = Keyword.fetch!(config, :api_key)
    params = email |> convert_to_mandrill_params(api_key) |> Poison.encode!
    case request!(@send_message_path, params) do
      %{status_code: status} = response when status > 299 ->
        raise(ApiError, %{params: params, response: response})
      response -> response
    end
  end

  def deliver_async(email, config) do
    Task.async(fn ->
      deliver(email, config)
    end)
  end

  defp convert_to_mandrill_params(email, api_key) do
    %{key: api_key, message: message_params(email)}
  end

  defp message_params(email) do
    %{
      from_email: email.from.address,
      from_name: email.from.name,
      to: recipients(email),
      subject: email.subject,
      text: email.text_body,
      html: email.html_body,
      headers: email.headers
    }
    |> add_message_params(email)
  end

  defp add_message_params(mandrill_message, %{private: %{message_params: message_params}}) do
    Enum.reduce(message_params, mandrill_message, fn({key, value}, mandrill_message) ->
      Map.put(mandrill_message, key, value)
    end)
  end
  defp add_message_params(mandrill_message, _), do: mandrill_message

  defp recipients(email) do
    []
    |> add_recipients(email.to, type: "to")
    |> add_recipients(email.cc, type: "cc")
    |> add_recipients(email.bcc, type: "bcc")
  end

  defp add_recipients(recipients, new_recipients, type: recipient_type) do
    Enum.reduce(new_recipients, recipients, fn(recipient, recipients) ->
      recipients ++ [%{
        name: recipient.name,
        email: recipient.address,
        type: recipient_type
      }]
    end)
  end

  defp headers do
    %{"content-type" => "application/json"}
  end

  defp request!(path, params) do
    HTTPoison.post!("#{base_uri}/#{path}", params, headers)
  end

  defp base_uri do
    Application.get_env(:bamboo, :mandrill_base_uri) || @default_base_uri
  end
end
