codeunit 72327 "DOPSWHS Environment Admin Mgmt"
{
    Permissions = tabledata "DOPSWHS Environment Admin" = rimd,
                  tabledata "DOPSWHS Local User" = rimd;

    procedure SaveAdmin(var User: Record "DOPSWHS Local User"; OldUser: Record "DOPSWHS Local User")
    var
        Admin: Record "DOPSWHS Environment Admin";
        AdminRef: RecordRef;
        UserRef: RecordRef;
        OldRef: RecordRef;
        FieldIds: List of [Integer];
        FieldId: Integer;
        TargetField: FieldRef;
        SourceField: FieldRef;
        OldField: FieldRef;
        LocationCode: Code[10];
        BinCode: Code[20];
    begin
        if User.IsTemporary() then
            exit;
        if not User."Terminal Admin" and not OldUser."Terminal Admin" then
            exit;
        if not User."Terminal Admin" then
            Error('Ortam yöneticisini normal kullanıcıya çevirmek yerine devre dışı bırakın.');
        User."Terminal Code" := '';
        Admin.LockTable();
        if not Admin.Get(User.Username) then begin
            Admin.TransferFields(User);
            Admin."Default Location Code" := '';
            Admin."Default Bin Code" := '';
            Admin.Insert(false);
        end else begin
            // Apply only changed shared fields, so a stale card cannot undo a
            // PIN reset or lockout from another company. Locations stay local.
            FieldIds.AddRange(10, 20, 21, 40, 50, 51, 60, 70, 71, 91, 92, 99);
            AdminRef.GetTable(Admin);
            UserRef.GetTable(User);
            OldRef.GetTable(OldUser);
            foreach FieldId in FieldIds do begin
                SourceField := UserRef.Field(FieldId);
                OldField := OldRef.Field(FieldId);
                if SourceField.Value <> OldField.Value then begin
                    TargetField := AdminRef.Field(FieldId);
                    TargetField.Value := SourceField.Value;
                end;
            end;
            AdminRef.SetTable(Admin);
            Admin.Modify(false);
        end;
        LocationCode := User."Default Location Code";
        BinCode := User."Default Bin Code";
        User.TransferFields(Admin);
        User."Default Location Code" := LocationCode;
        User."Default Bin Code" := BinCode;
        // The caller will write its own buffer after its table trigger returns.
        PublishAdmin(Admin, CompanyName());
    end;

    procedure EnsureCurrentCompany()
    var
        Admin: Record "DOPSWHS Environment Admin";
    begin
        Admin.LockTable();
        if Admin.FindSet() then
            repeat
                CopyToCompany(Admin, CompanyName());
            until Admin.Next() = 0;
    end;

    procedure PrepareLogin(Username: Code[20])
    var
        Admin: Record "DOPSWHS Environment Admin";
    begin
        // One lockout counter for the account across all companies.
        Admin.LockTable();
        if Admin.Get(Username) then
            CopyToCompany(Admin, CompanyName());
    end;

    local procedure PublishAdmin(Admin: Record "DOPSWHS Environment Admin"; SkipCompany: Text)
    var
        Company: Record Company;
    begin
        if Company.FindSet() then
            repeat
                if Company.Name <> SkipCompany then
                    CopyToCompany(Admin, Company.Name);
            until Company.Next() = 0;
    end;

    local procedure CopyToCompany(Admin: Record "DOPSWHS Environment Admin"; CompanyNameValue: Text)
    var
        User: Record "DOPSWHS Local User";
        Existing: Boolean;
        LocationCode: Code[10];
        BinCode: Code[20];
    begin
        User.ChangeCompany(CompanyNameValue);
        Existing := User.Get(Admin.Username);
        if Existing then begin
            if not User."Terminal Admin" then
                Error('%1 şirketinde %2 koduyla normal kullanıcı var. Yönetici aktarılamadı.', CompanyNameValue, Admin.Username);
            LocationCode := User."Default Location Code";
            BinCode := User."Default Bin Code";
        end;
        User.TransferFields(Admin);
        User."Default Location Code" := LocationCode;
        User."Default Bin Code" := BinCode;
        if Existing then
            User.Modify(false)
        else
            User.Insert(false);
    end;

    procedure MigrateAdmins()
    var
        Company: Record Company;
        User: Record "DOPSWHS Local User";
        Admin: Record "DOPSWHS Environment Admin";
    begin
        // Collect before publishing, preserving existing identities and PINs.
        if Company.FindSet() then
            repeat
                User.ChangeCompany(Company.Name);
                User.SetRange("Terminal Admin", true);
                if User.FindSet() then
                    repeat
                        if Admin.Get(User.Username) then begin
                            if (Admin."Password Hash" <> User."Password Hash") or
                               (Admin."Password Salt" <> User."Password Salt") or
                               (Admin.Disabled <> User.Disabled)
                            then
                                Error('%1 yönetici kodunun şirketler arasında PIN veya etkinlik ayarları farklı. Güncellemeden önce düzeltin.', User.Username);
                        end else begin
                            Admin.TransferFields(User);
                            Admin."Terminal Code" := '';
                            Admin."Default Location Code" := '';
                            Admin."Default Bin Code" := '';
                            Admin.Insert(false);
                        end;
                    until User.Next() = 0;
            until Company.Next() = 0;
        if Admin.FindSet() then
            repeat
                PublishAdmin(Admin, '');
            until Admin.Next() = 0;
    end;
}
