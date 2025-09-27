defmodule Captcha do
  defstruct [:image_base64, :token, :verify_code_id]
end

defmodule BBDCDN do
  @base_url "https://booking.bbdc.sg"
  @headers [
    {"User-Agent", "Mozilla/5.0 (X11; Linux x86_64; rv:142.0) Gecko/20100101 Firefox/142.0"},
    {"Accept", "application/json, text/plain, */*"},
    {"Content-Type", "application/json"}
  ]

  def login(username, password, captcha_details) do
    body = %{
      userId: username,
      userPass: password
    }

    response =
      Req.post!(
        url: @base_url <> "/bbdc-back-service/api/auth/checkIdAndPass",
        headers: @headers,
        json: body
      )

    IO.inspect(response.status)
    IO.inspect(response.body)
  end

  @spec get_login_captcha() :: Captcha | nil
  def get_login_captcha do
    with {:ok,
          %Req.Response{
            status: 200,
            body: %{
              "data" => %{
                "image" => image,
                "captchaToken" => token,
                "verifyCodeId" => verify_code_id
              }
            }
          }} <-
           Req.post(@base_url <> "/bbdc-back-service/api/auth/getLoginCaptchaImage",
             headers: @headers
           ) do
      {:ok,
       %Captcha{
         image_base64: image,
         token: token,
         verify_code_id: verify_code_id
       }}
    else
      {:error, reason} ->
        IO.inspect(reason)
        nil

      {:ok, %Req.Response{status: status}} ->
        IO.inspect(status)
        nil
    end
  end

  def write_captcha(base64_data) do
    encoded = String.replace_prefix(base64_data, "data:image/png;base64,", "")

    {:ok, binary} = Base.decode64(encoded)

    File.write!("captcha.png", binary)
  end
end
