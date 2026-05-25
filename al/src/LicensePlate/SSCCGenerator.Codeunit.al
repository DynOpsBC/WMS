codeunit 72042 "DOPSWHS SSCC Generator"
{
    Access = Public;

    procedure Generate(): Code[18]
    var
        Setup: Record "DOPSWHS Setup";
        NoSeries: Codeunit "No. Series";
        Telemetry: Codeunit "DOPSWHS Telemetry";
        Prefix: Text;
        SerialRef: Text;
        Base17: Text[17];
    begin
        Setup.Get('');
        Prefix := Setup."GS1 Company Prefix";
        if Prefix = '' then begin
            Prefix := '9999999';
            Telemetry.LogInfo('SSCC.ExtensionPrefix', 'GS1 company prefix is empty; using extension filler prefix.');
        end;
        Setup.TestField("SSCC No. Series");
        SerialRef := DigitsOnly(NoSeries.GetNextNo(Setup."SSCC No. Series"));
        Base17 := CopyStr('0' + Prefix + PadLeft(SerialRef, 16 - StrLen(Prefix), '0'), 1, 17);
        exit(CopyStr(Base17 + Format(CalculateCheckDigit(Base17)), 1, 18));
    end;

    procedure CalculateCheckDigit(SeventeenDigits: Text[17]): Char
    var
        I: Integer;
        Digit: Integer;
        Sum: Integer;
        Check: Integer;
    begin
        if StrLen(SeventeenDigits) <> 17 then
            Error('SSCC check digit requires 17 digits.');
        for I := 17 downto 1 do begin
            Evaluate(Digit, CopyStr(SeventeenDigits, I, 1));
            if ((17 - I + 1) mod 2) = 1 then
                Sum += Digit * 3
            else
                Sum += Digit;
        end;
        Check := (10 - (Sum mod 10)) mod 10;
        exit(CopyStr(Format(Check), 1, 1)[1]);
    end;

    local procedure PadLeft(Value: Text; Length: Integer; PadChar: Text[1]): Text
    begin
        while StrLen(Value) < Length do
            Value := PadChar + Value;
        exit(Value);
    end;

    local procedure DigitsOnly(Value: Text): Text
    var
        I: Integer;
        Result: Text;
        Ch: Text[1];
    begin
        for I := 1 to StrLen(Value) do begin
            Ch := CopyStr(Value, I, 1);
            if Ch in ['0' .. '9'] then
                Result += Ch;
        end;
        exit(Result);
    end;
}
