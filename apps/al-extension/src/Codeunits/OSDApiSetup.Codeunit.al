codeunit 50029000 "OSD Api Setup"
{
    Access = Internal;

    procedure StampSignIn(UserId: Code[50])
    var
        Worker: Record "OSD Worker";
    begin
        if not Worker.Get(UserId) then
            exit;
        Worker."Last Sign-In" := CurrentDateTime();
        Worker.Modify();
    end;
}
