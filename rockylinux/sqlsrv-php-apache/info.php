    <?php
    $con=new PDO(
        "sqlsrv:Server=localhost,1433;Database=master",
        "sa",
        getenv("MSSQL_SA_PASSWORD")
    );
    $stmt=$con->prepare("SELECT @@Version as SQL_VERSION, CURRENT_TIMESTAMP as TIME");
    $stmt->execute();
    $stmt->setFetchMode(PDO::FETCH_ASSOC);
    echo '<pre>';
    var_dump($stmt->fetch());
    echo '</pre>';
    echo phpinfo();
