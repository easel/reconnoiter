<html>
<head>
<meta http-equiv="Content-Type" content="text/html; charset=iso-8859-1" />
<title>Bandwidth Graph</title>
</head>
<body>
  <script type="text/javascript" src="js/swfobject.js"></script>
	<div id="flashcontent">
		<strong>You need to upgrade your Flash Player</strong>
	</div>

	<script type="text/javascript">
		// <![CDATA[		
		var so = new SWFObject("amcharts/amline/amline.swf", "amline", "780", "400", "8", "#FFFFFF");
		so.addVariable("path", "amcharts/amline/");
		so.addVariable("settings_file", escape("bw_settings.php?id=<?php print $_GET['id'] ?>&start=<?php print $_GET['start'] ?>&end=<?php print $_GET['end'] ?>&cnt=<?php print isset($_GET['cnt']) ? $_GET['cnt'] : 500 ?>"));
		so.addVariable("preloader_color", "#999999");
		so.write("flashcontent");
		// ]]>
	</script>
<!-- end of amline script -->
</body>
</html>
