defmodule Captcha do
  defstruct [:image_base64, :token, :verify_code_id]
end

defmodule CaptchaAnswer do
  defstruct [:token, :verify_code_id, :verify_code_value]
end

defmodule PracticalTraining do
  defstruct [:subject, :stage_no]
end

defmodule Session do
  defstruct [
    :slot_id,
    :slot_id_enc,
    :booking_progress_enc,
    :vehicle_type,
    :session_name,
    :date,
    :start_time,
    :end_time,
    :price
  ]
end

defmodule BBDCDN do
  @base_url "https://booking.bbdc.sg"
  @headers [
    {"User-Agent", "Mozilla/5.0 (X11; Linux x86_64; rv:142.0) Gecko/20100101 Firefox/142.0"},
    {"Accept", "application/json, text/plain, */*"},
    {"Content-Type", "application/json"}
  ]

  @spec login(String.t(), String.t(), CaptchaAnswer) :: String.t() | nil
  def login(username, password, captcha_details) do
    body = %{
      captchaToken: captcha_details.token,
      verifyCodeId: captcha_details.verify_code_id,
      verifyCodeValue: captcha_details.verify_code_value,
      userId: username,
      userPass: password
    }

    with {:ok,
          %Req.Response{
            status: 200,
            body: %{
              "data" => %{
                "tokenHeader" => "Authorization",
                "tokenContent" => auth_token
              }
            }
          }} <-
           Req.post(@base_url <> "/bbdc-back-service/api/auth/login",
             headers: @headers,
             json: body
           ) do
      auth_token
    else
      {:error, reason} ->
        IO.inspect(reason)
        nil

      {:ok, %Req.Response{status: status}} ->
        IO.inspect(status)
        nil
    end
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
      %Captcha{
        image_base64: image,
        token: token,
        verify_code_id: verify_code_id
      }
    else
      {:error, reason} ->
        IO.inspect(reason)
        nil

      {:ok, %Req.Response{status: status}} ->
        IO.inspect(status)
        nil
    end
  end

  @spec get_booking_captcha(String.t(), String.t()) :: Captcha | nil
  def get_booking_captcha(auth_token, jsession_token) do
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
           Req.post(@base_url <> "/bbdc-back-service/api/booking/manage/getCaptchaImage",
             headers: @headers ++ [{"Authorization", auth_token}, {"JSESSIONID", jsession_token}]
           ) do
      %Captcha{
        image_base64: image,
        token: token,
        verify_code_id: verify_code_id
      }
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

  def get_jsession_token(auth_token) do
    with {:ok,
          %Req.Response{
            status: 200,
            body: %{
              "data" => %{
                "activeCourseList" => [%{"courseType" => "2B", "authToken" => jsession_token}]
              }
            }
          }} <-
           Req.post(@base_url <> "/bbdc-back-service/api/account/listAccountCourseType",
             headers: @headers ++ [{"Authorization", auth_token}]
           ) do
      jsession_token
    else
      {:error, reason} ->
        IO.inspect(reason)
        nil

      {:ok, %Req.Response{} = res} ->
        IO.inspect(res)
        nil
    end
  end

  def list_modules(auth_token, jsession_token) do
    body = %{
      courseSubType: "Practical",
      courseType: "2B",
      pageNo: 1,
      pageSize: 10
    }

    with {:ok,
          %Req.Response{
            status: 200,
            body: %{"data" => %{"practicalTrainings" => trainings}}
          }} <-
           Req.post(
             @base_url <> "/bbdc-back-service/api/booking/c2practical/listPracticalTrainings",
             headers: @headers ++ [{"Authorization", auth_token}, {"JSESSIONID", jsession_token}],
             json: body
           ) do
      trainings
      |> Enum.filter(fn %{
                          "canDoBooking" => can_book,
                          "completeFlag" => has_completed
                        } ->
        can_book and not has_completed
      end)
      |> Enum.map(fn %{
                       "subDesc" => subject,
                       "subStageSubNo" => stage_no
                     } ->
        %PracticalTraining{
          subject: subject,
          stage_no: stage_no
        }
      end)
    else
      {:error, reason} ->
        IO.inspect(reason)
        nil

      {:ok, %Req.Response{} = res} ->
        IO.inspect(res)
        nil
    end
  end

  def get_sessions(auth_token, jession_token, module) do
    body = %{
      courseType: "2B",
      stageSubDesc: module.subject,
      stageSubNo: module.stage_no
    }

    get_by_month = fn month ->
      with {:ok,
            %Req.Response{
              status: 200,
              body: %{"data" => %{"releasedSlotListGroupByDay" => days}}
            }} <-
             Req.post(
               @base_url <> "/bbdc-back-service/api/booking/c2practical/listPracSlotReleased",
               headers:
                 @headers ++ [{"Authorization", auth_token}, {"JSESSIONID", jession_token}],
               json: Map.merge(body, %{releasedSlotMonth: month["slotMonthYm"]})
             ) do
        days
        |> Map.values()
        |> List.flatten()
        |> Enum.filter(fn %{"bookingProgress" => status} ->
          status == "Available"
        end)
        |> Enum.map(fn session ->
          %Session{
            slot_id: session["slotId"],
            slot_id_enc: session["slotIdEnc"],
            booking_progress_enc: session["bookingProgressEnc"],
            vehicle_type: "Circuit",
            session_name: session["slotRefName"],
            date: session["slotRefDate"],
            start_time: session["startTime"],
            end_time: session["endTime"],
            price: session["totalFee"]
          }
        end)
      else
        _ -> []
      end
    end

    with {:ok,
          %Req.Response{
            status: 200,
            body: %{"data" => %{"releasedSlotMonthList" => months}}
          }} <-
           Req.post(
             @base_url <> "/bbdc-back-service/api/booking/c2practical/listPracSlotReleased",
             headers: @headers ++ [{"Authorization", auth_token}, {"JSESSIONID", jession_token}],
             json: body
           ) do
      months
      |> Enum.flat_map(get_by_month)
      |> Enum.sort_by(fn %Session{date: date, session_name: name} ->
        {date, name}
      end)
    else
      {:error, reason} ->
        IO.inspect(reason)
        nil

      {:ok, %Req.Response{} = res} ->
        IO.inspect(res)
        nil
    end
  end

  def main(username, password) do
    auth_token =
      with %Captcha{image_base64: base64_image, token: token, verify_code_id: verify_code_id} <-
             get_login_captcha() do
        write_captcha(base64_image)
        input = IO.gets("Enter captcha: ") |> String.trim()

        answer = %CaptchaAnswer{
          token: token,
          verify_code_id: verify_code_id,
          verify_code_value: input
        }

        login(username, password, answer)
      end

    jsession_token = get_jsession_token(auth_token)
    Process.sleep(500)

    modules = list_modules(auth_token, jsession_token)
    Process.sleep(500)

    sessions =
      with [%PracticalTraining{} = t] <- modules do
        get_sessions(auth_token, jsession_token, t)
        Process.sleep(500)
      end

    session = select_sessions(sessions)

    _ =
      with %Captcha{image_base64: base64_image, token: token, verify_code_id: verify_code_id} <-
             get_booking_captcha(auth_token, jsession_token) do
        write_captcha(base64_image)
        input = IO.gets("Enter captcha: ") |> String.trim()

        answer = %CaptchaAnswer{
          token: token,
          verify_code_id: verify_code_id,
          verify_code_value: input
        }

        book_session(auth_token, jsession_token, answer, session)
      end

    # TODO cancel booking before book
  end
end
