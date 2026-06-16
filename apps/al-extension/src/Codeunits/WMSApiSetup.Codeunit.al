codeunit 50029000 "WMS Api Setup"
{
    Access = Internal;

    procedure StampSignIn(UserId: Code[50])
    var
        Worker: Record "WMS Worker";
    begin
        if not Worker.Get(UserId) then
            exit;
        Worker."Last Sign-In" := CurrentDateTime();
        Worker.Modify();
    end;
}
