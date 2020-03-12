import groovy.sql.Sql
import groovy.transform.CompileStatic

import java.sql.Connection
import java.sql.DriverManager
import java.sql.SQLException
import java.util.logging.Logger

@CompileStatic
class DBConfig {
    static Logger logger = Logger.getLogger("")

    final String url
    final Properties connectionProperties
    private final Closure<Connection> connect

    DBConfig(String url, Properties connectionProperties, Closure<Connection> connect) {
        this.url = url
        this.connectionProperties = connectionProperties
        this.connect = connect
    }

    def <V> V withSql(Closure<V> thunk) throws SQLException {
        Connection conn = connect(url, connectionProperties)
        Sql sql = new Sql(conn)
        try {
            thunk(sql)
        } finally {
            sql.close()
            conn.close()
        }
    }

    static Properties jdbcProperties(Properties dbProperties) {
        Closure<String> config = {
            def name = "db.${it}"
            def val = dbProperties.getProperty(name)
            if (val == null) {
                throw new IllegalStateException(name)
            }
            val
        }
        def driver = config("driver")
        try {
            Class.forName(driver)
        } catch (Exception noDriver) {
            logger.exiting("cannot load driver", driver, noDriver)
            throw noDriver
        }
        Properties properties = new Properties()
        properties.setProperty('url', config("url"))
        properties.setProperty('user', config("username"))
        properties.setProperty('password', config('password'))
        properties
    }

    static DBConfig inMemoryDB(String databaseName, boolean reset=false) {
        String url = "jdbc:h2:mem:${databaseName};create=true"
        DBConfig it = new DBConfig(url, new Properties(),
                { String ignored, Properties _ -> DriverManager.getConnection(url) })
        if (reset) {
            it.withSql({ Sql sql -> sql.execute('drop all objects') })
        }
        it
    }

    interface Task {
        boolean complete()

        void run()
    }

    static class CLI {
        protected final Map opts
        private final Closure<Properties> fetchProperties
        private Properties configCache = null
        private final Closure<Void> exit
        private final Closure<Connection> getConnection

        CLI(Map opts, Closure<Properties> getProperties, Closure exit, Closure<Connection> getConnection) {
            this.opts = opts
            this.fetchProperties = getProperties
            this.exit = exit
            this.getConnection = getConnection
        }

        boolean flag(String target) {
            opts[target] == true
        }

        String arg(String target, String fallback=null) {
            if (!opts.containsKey(target) || opts[target] == null) {
                return fallback
            }
            opts[target]
        }

        // ISSUE: ambient; constructor should take makeURL()
        URL urlArg(String target) {
            URI cwd = new File(System.getProperty('user.dir')).toURI()
            cwd.resolve(arg(target)).toURL()
        }

        String property(String target) {
            String value = getConfig().getProperty(target)
            if (value == null) {
                throw new IllegalArgumentException(target)
            }
            value
        }

        // ISSUE: ambient; constructor should take makeURL()
        URL urlProperty(String target) {
            URI cwd = new File(System.getProperty('user.dir')).toURI()
            cwd.resolve(property(target)).toURL()
        }

        DBConfig account() {
            Properties config = getConfig()
            try {
                config = jdbcProperties(config)
            } catch (IllegalStateException oops) {
                logger.warning("Config missing property: $oops")
                exit(1)
            } catch (ClassNotFoundException oops) {
                logger.warning("driver not found (fix CLASSPATH?): $oops")
                exit(1)
            }
            String url = config.getProperty('url')
            logger.info("DB: $url")
            new DBConfig(url, config, getConnection)
        }

        // a bit of a kludge
        private Properties getConfig() {
            if (configCache != null) {
                return configCache
            }
            String db = arg("--db")
            if (!db) {
                logger.warning("expected --db=PROPS")
                exit(1)
            }
            logger.info("getting config from $db")
            try {
                configCache = fetchProperties(db)
            } catch (IOException oops) {
                logger.warning("cannot load properties from ${db}: $oops")
            }
            configCache
        }
    }
}