-- ThemeConfig: clean white / light blue / light gray UI theme. Tweak visuals here only.
-- Built-in Roblox fonts only (Gotham family), no external assets.

local Theme = {}

Theme.Colors = {
	Background = Color3.fromRGB(255, 255, 255),
	Surface = Color3.fromRGB(247, 250, 253),
	SurfaceAlt = Color3.fromRGB(237, 243, 249),
	Gray = Color3.fromRGB(229, 233, 238),
	GrayDark = Color3.fromRGB(196, 203, 212),
	Accent = Color3.fromRGB(88, 162, 236),
	AccentSoft = Color3.fromRGB(221, 237, 252),
	AccentDark = Color3.fromRGB(44, 110, 184),
	SkyTop = Color3.fromRGB(255, 255, 255),
	SkyBottom = Color3.fromRGB(214, 234, 252),
	Text = Color3.fromRGB(28, 40, 56),
	TextMuted = Color3.fromRGB(114, 127, 145),
	TextOnAccent = Color3.fromRGB(255, 255, 255),
	Stroke = Color3.fromRGB(219, 228, 238),
	Danger = Color3.fromRGB(218, 92, 92),
	DangerSoft = Color3.fromRGB(252, 233, 233),
	Disabled = Color3.fromRGB(232, 236, 241),
	Success = Color3.fromRGB(64, 168, 108),
	SuccessSoft = Color3.fromRGB(225, 245, 233),
	Warning = Color3.fromRGB(226, 152, 52),
	WarningSoft = Color3.fromRGB(253, 241, 222),
	StatusGreen = Color3.fromRGB(64, 176, 110),
	StatusRed = Color3.fromRGB(222, 88, 88),
	StatusGrey = Color3.fromRGB(170, 178, 189),
}

Theme.Fonts = {
	Regular = Enum.Font.Gotham,
	Medium = Enum.Font.GothamMedium,
	Bold = Enum.Font.GothamBold,
	Title = Enum.Font.GothamBlack,
}

Theme.TextSize = {
	Tiny = 11,
	Small = 12,
	Body = 14,
	Title = 18,
	Header = 22,
	Hero = 60,
}

Theme.Radius = {
	Small = 8,
	Medium = 12,
	Large = 16,
	Pill = 999,
}

Theme.Motion = {
	Fast = 0.12,
	Normal = 0.22,
	Slow = 0.35,
	Hero = 0.8,
	Style = Enum.EasingStyle.Quint,
	Direction = Enum.EasingDirection.Out,
}

return Theme
