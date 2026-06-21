codeunit 72082 "DOPSWHS License Mgmt"
{
    Access = Public;

    var
        VerifyEvery: Duration; // 1 hour
        GraceDays: Integer;    // 7

    trigger OnRun()
    begin
        VerifyEvery := 60 * 60 * 1000;
        GraceDays := 7;
        TryVerify(false);
    end;

    procedure VerifyNow(): Boolean
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if not Setup.Get('') then exit(false);
        exit(TryVerify(true));
    end;

    procedure CurrentTier(): Enum "DOPSWHS License Tier"
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if not Setup.Get('') then exit(Enum::"DOPSWHS License Tier"::Essentials);
        case Setup."License Tier" of
            Setup."License Tier"::Essentials: exit(Enum::"DOPSWHS License Tier"::Essentials);
            Setup."License Tier"::Advanced: exit(Enum::"DOPSWHS License Tier"::Advanced);
            Setup."License Tier"::Enterprise: exit(Enum::"DOPSWHS License Tier"::Enterprise);
        end;
        exit(Enum::"DOPSWHS License Tier"::Essentials);
    end;

    procedure IsActive(): Boolean
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if not Setup.Get('') then exit(false);
        exit((Setup."License Status" = Setup."License Status"::Active) or
             (Setup."License Status" = Setup."License Status"::Offline));
    end;

    procedure GuardFeature(Feature: Enum "DOPSWHS License Feature")
    var
        Setup: Record "DOPSWHS Setup";
        Tier: Enum "DOPSWHS License Tier";
        Required: Enum "DOPSWHS License Tier";
        ErrFeatureBlockedLbl: Label 'Feature %1 requires the %2 tier. Current license: %3.', Comment = '%1=feature, %2=required tier, %3=current tier';
        ErrLicenseInactiveLbl: Label 'License is not active (%1). %2', Comment = '%1=status, %2=message';
    begin
        if not Setup.Get('') then exit;
        if not IsActive() then
            Error(ErrLicenseInactiveLbl, Format(Setup."License Status"), Setup."License Status Message");

        Tier := CurrentTier();
        Required := RequiredTierFor(Feature);
        if TierValue(Tier) < TierValue(Required) then
            Error(ErrFeatureBlockedLbl, Format(Feature), Format(Required), Format(Tier));
    end;

    procedure GuardSeats(SeatsToAdd: Integer)
    var
        Setup: Record "DOPSWHS Setup";
        DeviceReg: Record "DOPSWHS Device Registration";
        UsedSeats: Integer;
        Limit: Integer;
        ErrSeatsLbl: Label 'License seat limit reached (%1 of %2). Upgrade the license or remove inactive devices.', Comment = '%1=used, %2=limit';
    begin
        if not Setup.Get('') then exit;
        if not IsActive() then exit;
        Limit := Setup."License Seats";
        if Limit <= 0 then exit;
        if DeviceReg.IsEmpty() then
            UsedSeats := 0
        else
            UsedSeats := DeviceReg.Count();
        if UsedSeats + SeatsToAdd > Limit then
            Error(ErrSeatsLbl, UsedSeats, Limit);
    end;

    procedure StatusBannerText(): Text
    var
        Setup: Record "DOPSWHS Setup";
        ActiveLbl: Label 'License active — %1 (%2 seat, expires %3)', Comment = '%1=tier, %2=seats, %3=date';
        InactiveLbl: Label 'License %1 — %2', Comment = '%1=status, %2=message';
    begin
        if not Setup.Get('') then exit('');
        if Setup."License Status" = Setup."License Status"::Active then
            exit(StrSubstNo(ActiveLbl, Format(Setup."License Tier"), Setup."License Seats", Format(Setup."License Expires At", 0, '<Day,2>/<Month,2>/<Year4>')));
        exit(StrSubstNo(InactiveLbl, Format(Setup."License Status"), Setup."License Status Message"));
    end;

    local procedure RequiredTierFor(Feature: Enum "DOPSWHS License Feature"): Enum "DOPSWHS License Tier"
    begin
        case Feature of
            Feature::PrintBridge: exit(Enum::"DOPSWHS License Tier"::Advanced);
            Feature::QualityMgmt: exit(Enum::"DOPSWHS License Tier"::Advanced);
            Feature::Production: exit(Enum::"DOPSWHS License Tier"::Enterprise);
            Feature::WebhookPublish: exit(Enum::"DOPSWHS License Tier"::Advanced);
            else
                exit(Enum::"DOPSWHS License Tier"::Essentials);
        end;
    end;

    local procedure TierValue(Tier: Enum "DOPSWHS License Tier"): Integer
    begin
        case Tier of
            Tier::Essentials: exit(0);
            Tier::Advanced: exit(1);
            Tier::Enterprise: exit(2);
        end;
        exit(0);
    end;

    local procedure TryVerify(Force: Boolean): Boolean
    var
        Setup: Record "DOPSWHS Setup";
        Client: HttpClient;
        Content: HttpContent;
        Response: HttpResponseMessage;
        ContentHeaders: HttpHeaders;
        ResponseText: Text;
        ResponseJson: JsonObject;
        ValidValue: JsonToken;
        TierTxt: Text;
        SeatsTxt: Text;
        ExpiresTxt: Text;
        EmailTxt: Text;
        ReasonTxt: Text;
        Url: Text;
        BodyTxt: Text;
        TenantId: Text;
    begin
        if not Setup.Get('') then exit(false);
        if Setup."License Service URL" = '' then begin
            UpdateStatus(Setup."License Status"::Unknown, 'No License Service URL configured.', 0DT, 0, '');
            exit(false);
        end;
        if Setup."License Key" = '' then begin
            UpdateStatus(Setup."License Status"::Invalid, 'No License Key configured.', 0DT, 0, '');
            exit(false);
        end;

        if (not Force) and (Setup."License Last Verified At" <> 0DT) then
            if (CurrentDateTime() - Setup."License Last Verified At" < VerifyEvery) then
                exit(IsActive());

        TenantId := GetAadTenantId();
        Url := RTrim(Setup."License Service URL", '/') + '/api/license/verify';
        BodyTxt := StrSubstNo('{"tenantId":"%1","key":"%2"}', TenantId, Setup."License Key");
        Content.WriteFrom(BodyTxt);
        Content.GetHeaders(ContentHeaders);
        ContentHeaders.Remove('Content-Type');
        ContentHeaders.Add('Content-Type', 'application/json');

        if not Client.Post(Url, Content, Response) then begin
            ApplyOfflineGrace(Setup);
            exit(IsActive());
        end;
        Response.Content().ReadAs(ResponseText);
        if not Response.IsSuccessStatusCode() then begin
            ApplyOfflineGrace(Setup);
            exit(IsActive());
        end;
        if not ResponseJson.ReadFrom(ResponseText) then begin
            UpdateStatus(Setup."License Status"::Invalid, 'Could not parse license response.', 0DT, 0, '');
            exit(false);
        end;
        if not ResponseJson.Get('valid', ValidValue) then begin
            UpdateStatus(Setup."License Status"::Invalid, 'License response missing valid flag.', 0DT, 0, '');
            exit(false);
        end;

        if not ValidValue.AsValue().AsBoolean() then begin
            ReasonTxt := ReadString(ResponseJson, 'reason');
            UpdateStatus(MapReason(ReasonTxt), StrSubstNo('Verification failed (%1)', ReasonTxt), 0DT, 0, '');
            exit(false);
        end;

        TierTxt := ReadString(ResponseJson, 'tier');
        SeatsTxt := ReadString(ResponseJson, 'seats');
        ExpiresTxt := ReadString(ResponseJson, 'expiresAt');
        EmailTxt := ReadString(ResponseJson, 'email');

        Setup.Get('');
        Setup."License Tier" := DecodeTier(TierTxt);
        Setup."License Seats" := DecodeInt(SeatsTxt);
        Setup."License Expires At" := DecodeDateTime(ExpiresTxt);
        Setup."License Email" := CopyStr(EmailTxt, 1, MaxStrLen(Setup."License Email"));
        Setup."License Status" := Setup."License Status"::Active;
        Setup."License Status Message" := '';
        Setup."License Last Verified At" := CurrentDateTime();
        Setup.Modify(true);
        exit(true);
    end;

    local procedure UpdateStatus(NewStatus: Enum "DOPSWHS License Status"; Message: Text; ExpiresAt: DateTime; Seats: Integer; Email: Text)
    var
        Setup: Record "DOPSWHS Setup";
    begin
        if not Setup.Get('') then exit;
        Setup."License Status" := NewStatus;
        Setup."License Status Message" := CopyStr(Message, 1, MaxStrLen(Setup."License Status Message"));
        if ExpiresAt <> 0DT then
            Setup."License Expires At" := ExpiresAt;
        if Seats > 0 then
            Setup."License Seats" := Seats;
        if Email <> '' then
            Setup."License Email" := CopyStr(Email, 1, MaxStrLen(Setup."License Email"));
        Setup."License Last Verified At" := CurrentDateTime();
        Setup.Modify(true);
    end;

    local procedure ApplyOfflineGrace(var Setup: Record "DOPSWHS Setup")
    var
        GraceUntil: DateTime;
    begin
        if Setup."License Last Verified At" = 0DT then begin
            UpdateStatus(Setup."License Status"::Invalid, 'License service unreachable; no prior verification.', 0DT, 0, '');
            exit;
        end;
        GraceUntil := Setup."License Last Verified At" + (GraceDays * 24 * 60 * 60 * 1000);
        if CurrentDateTime() <= GraceUntil then
            UpdateStatus(Setup."License Status"::Offline,
                StrSubstNo('Service unreachable; using cached verification until %1.', Format(GraceUntil, 0, '<Day,2>/<Month,2>/<Year4>')),
                0DT, 0, '')
        else
            UpdateStatus(Setup."License Status"::Expired,
                'Offline grace period exceeded. Reconnect to refresh license.', 0DT, 0, '');
    end;

    local procedure MapReason(Reason: Text): Enum "DOPSWHS License Status"
    begin
        case LowerCase(Reason) of
            'expired': exit(Enum::"DOPSWHS License Status"::Expired);
            'revoked': exit(Enum::"DOPSWHS License Status"::Revoked);
            'superseded': exit(Enum::"DOPSWHS License Status"::Revoked);
            else
                exit(Enum::"DOPSWHS License Status"::Invalid);
        end;
    end;

    local procedure ReadString(JObj: JsonObject; Key: Text): Text
    var
        Token: JsonToken;
    begin
        if JObj.Get(Key, Token) then
            if not Token.AsValue().IsNull then
                exit(Token.AsValue().AsText());
        exit('');
    end;

    local procedure DecodeTier(Source: Text): Option Essentials,Advanced,Enterprise
    begin
        case LowerCase(Source) of
            'enterprise': exit(2);
            'advanced': exit(1);
            else
                exit(0);
        end;
    end;

    local procedure DecodeInt(Source: Text): Integer
    var
        Result: Integer;
    begin
        if Evaluate(Result, Source) then exit(Result);
        exit(0);
    end;

    local procedure DecodeDateTime(Source: Text): DateTime
    var
        Result: DateTime;
    begin
        if Source = '' then exit(0DT);
        if Evaluate(Result, Source, 9) then exit(Result);
        exit(0DT);
    end;

    local procedure GetAadTenantId(): Text
    begin
        exit(LowerCase(Format(Database.AadTenantId())));
    end;

    local procedure RTrim(Source: Text; Char: Char): Text
    var
        L: Integer;
    begin
        L := StrLen(Source);
        while (L > 0) and (Source[L] = Char) do
            L -= 1;
        exit(CopyStr(Source, 1, L));
    end;
}
