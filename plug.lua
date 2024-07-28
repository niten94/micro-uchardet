VERSION = "1.1.2"

local micro = import("micro")
local config = import("micro/config")
local buffer = import("micro/buffer")
local shell = import("micro/shell")

local function runcmd(buf)
    local cmd = {}
    local pathind
    for item in buf.Settings["uchardet.command"]:gmatch("[^%s]+") do
        table.insert(cmd, item)
        if item == "%" then pathind = #cmd end
    end

    if #cmd < 2 then return nil, "less than 1 argument in command option" end
    if not pathind then return nil, "path placeholder not in command option" end
    return cmd, pathind
end

local function detect(buf)
    if buf.Type.Scratch or buf.Path == "" or buf:Modified() then
        return nil, "buffer not saved"
    end

    local cmd, pathind = runcmd(buf)
    if not cmd then return nil, pathind end

    cmd[pathind] = buf.Path
    local encd, err = shell.ExecCommand(unpack(cmd))
    if err then
        encd = encd and encd:match("(.-)%s*$") or ""
        return nil, encd == "" and err:Error() or err:Error() .. ": " .. encd
    end

    local revsep = encd:reverse():find(" :")
    encd = encd:match("(.-)%s*$", revsep and #encd - revsep + 2 or nil)
    if not encd then return nil, "cannot parse command output" end
    return encd:lower(), nil
end

local function dosfmt(buf)
    local cr, ln = ("\r"):byte(), buf:LineBytes(0)
    return #ln >= 2 and ln[#ln] == 0 and ln[#ln - 1] == cr
end

local function reopen(buf, encd)
    if dosfmt(buf) then buf:SetOption("fileformat", "dos") end

    -- TODO: workaround bug where differences in content are not read properly
    -- when reopening buffer: https://github.com/zyedidia/micro/issues/3303
    local format = buf.Settings["fileformat"]
    local cursors, loc
    if format == "dos" then
        cursors, loc = buf:GetCursors(), {}
        for _, cur in cursors() do table.insert(loc, -cur.Loc) end
        buf:Replace(buf:Start(), buf:End(), "")
    end

    local err = buf:SetOption("encoding", encd)
    err = err and encd .. ": " .. err:Error() or nil
    if not err then
        err = buf:ReOpen()
        err = err and "cannot reopen buffer" .. ": " .. err:Error() or nil
    end

    if err then
        if format == "dos" then buf:Undo() end
        return err
    end

    if format ~= "dos" then return nil end
    for i, cur in cursors() do cur:GotoLoc(loc[i]) end
    buf:RelocateCursors()
    return nil
end

local function cmdhndl(bp, args)
    local err
    if #args > 0 then
        err = "arguments not handled"
    else
        local buf, encderr, encd = bp.Buf, "cannot detect encoding"
        encd, err = detect(buf)
        if not err then
            err = encd == "unknown" and encderr or reopen(buf, encd)
        end
    end

    if err then micro.InfoBar():Error(err) end
end

function onBufferOpen(buf)
    local onopen = buf.Settings["uchardet.onopen"]
    if not onopen or buf.Type.Scratch or buf.Path == "" then return end

    local encd, err = detect(buf)
    if encd == "unknown" then return end
    if not err then err = reopen(buf, encd) end
    if err then micro.InfoBar():Error("uchardet: " .. err) end
end

function preinit()
    config.RegisterCommonOption("uchardet", "command", "uchardet -- %")
    config.RegisterCommonOption("uchardet", "onopen", false)
end

function init()
    config.MakeCommand("uchardet", cmdhndl, config.NoComplete)
    config.AddRuntimeFile("uchardet", config.RTHelp, "help/uchardet.md")
end
