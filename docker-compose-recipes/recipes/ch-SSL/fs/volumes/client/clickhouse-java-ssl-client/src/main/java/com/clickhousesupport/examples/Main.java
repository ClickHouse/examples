package com.clickhousesupport.examples;

import static java.lang.System.exit;

import java.sql.Connection;
import java.sql.ResultSet;
import java.sql.Statement;
import java.util.Properties;

import com.clickhouse.jdbc.ClickHouseDataSource;

public class Main {

    static Connection getDataSourceConnection() {
        String url = "jdbc:clickhouse://clickhouse:8443/default";
        Properties properties = new Properties();
        properties.setProperty("ssl", "true");
        properties.setProperty("sslMode", "STRICT");
        ClickHouseDataSource dataSource = null;
        Connection conn = null;
        try {
            dataSource = new ClickHouseDataSource(url, properties);
            conn = dataSource.getConnection("default", "");
            return conn;
        } catch (Exception e) {
            System.out.println("error " + e.getMessage());
            exit(1);
        }
        return null;
    }

    public static void main(String[] args) {
        System.out.println("Starting SSL client...");
        try {
            System.out.println("connecting to ClickHouse...");
            Connection conn = getDataSourceConnection();
            if (conn == null) {
                throw new Exception("Invalid datasource connection");
            }
            System.out.println("launching query...");
            Statement stmt = conn.createStatement();
            ResultSet rs = stmt.executeQuery("select * from numbers(5)");
            while (rs.next()) {
                System.out.println((rs.getInt(1)));
            }

        } catch (Exception e) {
            System.out.println("error " + e.getMessage());
            exit(1);
        }

    }
}
