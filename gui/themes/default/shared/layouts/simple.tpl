<!DOCTYPE html>
<html>
<head>
	<title>{TR_PAGE_TITLE}</title>
	<meta name="robots" content="nofollow, noindex"/>
	<meta http-equiv="Content-Type" content="text/html; charset={THEME_CHARSET}"/>
	<meta http-equiv="Content-Script-Type" content="text/javascript"/>
	<link href="{THEME_ASSETS_PATH}/css/imscp.css?v={THEME_ASSETS_VERSION}" rel="stylesheet" type="text/css"/>
	<link href="{THEME_ASSETS_PATH}/css/{THEME_COLOR}.css?v={THEME_ASSETS_VERSION}" rel="stylesheet" type="text/css"/>
	<link href="{THEME_ASSETS_PATH}/css/jquery-ui-{THEME_COLOR}.css?v={THEME_ASSETS_VERSION}" rel="stylesheet"
		  type="text/css"/>
	<script type="text/javascript" src="{THEME_ASSETS_PATH}/js/jquery.js?v={THEME_ASSETS_VERSION}"></script>
	<script type="text/javascript" src="{THEME_ASSETS_PATH}/js/jquery.ui.js?v={THEME_ASSETS_VERSION}"></script>
	<script type="text/javascript"
			src="{THEME_ASSETS_PATH}/js/jquery.imscpTooltip-min.js?v={THEME_ASSETS_VERSION}"></script>
	<script type="text/javascript">
		/*<![CDATA[*/
		$(document).ready(function () {
			setTimeout(function () {
				$('.error, .success').fadeOut(1000);
			}, 5000);
			$('.body a').imscpTooltip();
			$('button').button({icons: {secondary: "ui-icon-triangle-1-e"}});
			$('input').first().focus();
		});
		/*]]>*/
	</script>
</head>
<body class="{CONTEXT_CLASS} no_menu">
<div id="header">
	<div id="logo"><span>{productLongName}</span></div>
	<div id="copyright"><span><a href="{productLink}" target="blank">{productCopyright}</a></span></div>
</div>
<div id="messageContainer">
	<!-- BDP: page_message -->
	<div id="message" class="{MESSAGE_CLS}">{MESSAGE}</div>
	<!-- EDP: page_message -->
</div>
<div class="body">
	{LAYOUT_CONTENT}
</div>
</body>
</html>
