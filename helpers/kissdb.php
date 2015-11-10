<?php
/*
 * kissdb.php
 *
 * Copyright (C) 2015 KISS IT Consulting <http://www.kissitconsulting.com/>
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above
 *    copyright notice, this list of conditions and the following
 *    disclaimer in the documentation and/or other materials
 *    provided with the distribution.
 * 
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
 * "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
 * LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL ANY
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 * NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 * SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
class kissdb
{
    private $host           = null;
    private $user           = null;
    private $password       = null;
    private $database       = null;
    private $result         = null;
    private $queue          = array();
    private $queue_count    = 0;
    private $redis_cache    = null;
    private $redis_db       = 0;
    public $db              = null;

    function __construct($host, $user, $password, $database, $auto_connect = true, $redis_cache = null, $redis_db = 0) {
        $this->host     = $host;
        $this->user     = $user;
        $this->password = $password;
        $this->database = $database;

        // Call connect if we want to do that already
        if($auto_connect) {
            $this->connect();
        }

        if(is_object($redis_cache)) {
            $this->redis_cache = $redis_cache;
            $this->redis_db = (int)$redis_db;
        }
    }

    // Function to connect to DB
    public function connect() {
        if($this->db === null) {
            $this->db = new mysqli($this->host, $this->user, $this->password, $this->database);
            if($this->db->connect_error) {
                throw new Exception( 'Connect Error: ' . $this->db->connect_error . ' ('.$this->db->connect_errno . ')' );
            }
        }
    }
   
    // Function to force a reconnect to the DB
    public function reconnect() {
        $this->close();
        $this->connect();
    }

    // Function to close DB
    public function close() {
        if($this->db) {
            $this->db->close();
        }
        $this->db = null;
    }

    // Function to check if we have results set in redis cache
    private function check_cache($sql) {
        $return = false;
        $sql = md5($sql);
        $this->redis_cache->use_db($this->redis_db);
        $check = $this->redis_cache->redis->get($sql);
        if($check !== false) {
            $return = $check;
        }
        return $return;
    }

    // Function to set results in redis cache.  This will handle passing $data as an array (but care should be taken)
    private function set_cache($sql, $data, $ttl) {
        $sql = md5($sql);
        $ttl = (int)$ttl;
        if(is_array($data)) {
            $data = serialize($data);
        }
        $this->redis_cache->use_db($this->redis_db);
        $this->redis_cache->redis->set($sql, $data, $ttl);
    }

    // Function to get the number of affected rows from the last operation
    public function getAffectedRows() {
        return $this->db->affected_rows;
    }

    // Function to run a query and handle failures.
    public function query($sql) {
        // Make sure we're connected in cases where we lazy connect
        $this->connect();
        $this->result = $this->db->query($sql);
        if($this->result === false) {
            throw new Exception( "Query Error: " . $this->db->error . " (".$this->db->errno . ").  SQL: $sql" );
        }
        return true;
    }

    // Function to get an array.  Pass key to have the array keyed by that column if it exists.  Note that this may lead to
    // unexpected results depending on data.
    public function getArray($sql, $key = false, $cache = false, $ttl = 0) {
        $return = array();
        if($cache && $this->redis_cache) {
            // Try the cache first
            $check = $this->check_cache($sql);
            if($check !== false) {
                return unserialize($check);
            }
        }

        // Get it from the DB if we didn't find it in cache (or don't want to use cache)
        $this->query($sql);
        while($row = $this->result->fetch_assoc()) {
            if($key && isset($row[$key])) {
                $return[$row[$key]] = $row;
            } else {
                $return[] = $row;
            }
        }
        
        // Set cache if we want to
        if($cache && $this->redis_cache) {
            $this->set_cache($sql, $return, $ttl);
        }
        return $return;
    }

    // Function to get a single row from the database as an array.  If your query returns more than one row you will get the first.
    public function getRow($sql, $cache = false, $ttl = 0) {
        $return = array();
        if($cache && $this->redis_cache) {
            // Try the cache first
            $check = $this->check_cache($sql);
            if($check !== false) {
                return unserialize($check);
            }
        }

        // Get it from the DB if we didn't find it in cache (or don't want to use cache)
        if($this->query($sql)) {
            $return = $this->result->fetch_assoc();
        }
        
        // Set cache if we want to
        if($cache && $this->redis_cache) {
            $this->set_cache($sql, $return, $ttl);
        }
        return $return;
    }

    // Function to get a single item from the database.  If your query returns more than one row/column you will get the first of each.
    public function getOne($sql, $cache = false, $ttl = 0) {
        $return = false;
        if($cache && $this->redis_cache) {
            // Try the cache first
            $check = $this->check_cache($sql);
            if($check !== false) {
                return $check;
            }
        }

        // Get it from the DB if we didn't find it in cache (or don't want to use cache)
        if($this->query($sql)) {
            $return = $this->result->fetch_array(MYSQLI_NUM);
            if(!empty($return)) {
                $return = $return[0];
            }
        }
        
        // Set cache if we want to
        if($cache && $this->redis_cache) {
            $this->set_cache($sql, $return, $ttl);
        }
        return $return;
    }

    // Function to insert a row into a table from an array.  Returns the id of the row (if applicable)
    public function insert($table, $row) {
        $return = 0;
        if(!empty($table) && is_array($row) && !empty($row)) {
            $row = array_map(array($this->db, 'real_escape_string'), $row);
            $sql = "INSERT INTO $table(".implode(",", array_keys($row)).") VALUES('".implode("','", $row)."')";
            $this->query($sql);
            $return = $this->db->insert_id;
        }
        return $return;
    }

    // Function to update a row from an array.
    public function update($table, $row, $where = array()) {
        if(!empty($table) && is_array($row) && !empty($row) && is_array($where)) {
            $set_array = array();
            $where_array = array();
            foreach($row as $key => $value) {
                $value = $this->escape($value);
                $set_array[] = "$key='$value'";
            }
            foreach($where as $key => $value) {
                $value = $this->escape($value);
                $where_array[] = "$key='$value'";
            }

            if(!empty($where_array)) {
                $sql = "UPDATE $table SET ".implode(", ", $set_array)." WHERE ".implode(" AND ", $where_array);
            } else {
                $sql = "UPDATE $table SET ".implode(", ", $set_array);
            }
            $this->query($sql);
        }
    }

    // Function to delete a row
    public function delete($table, $where) {
        if(!empty($table) && is_array($where) && !empty($where)) {
            $where_array = array();
            foreach($where as $key => $value) {
                $value = $this->escape($value);
                $where_array[] = "$key='$value'";
            }
            $sql = "DELETE FROM $table WHERE ".implode(" AND ", $where_array);
            $this->query($sql);
        }
    }

    // Function to escape a string
    public function escape($str) {
        if($this->db !== null) {
            // If we have a connection open use the proper function
            return $this->db->real_escape_string($str);
        } else {
            // Try to be safe when we don't want to open a connection
            return mysql_escape_string($str);
        }
    }

    // Function to queue updates and optionally run them if we hit the queue limit
    public function queueQuery($sql, $max = 0) {
        if(!empty($sql)) {
            $this->queue[] = $sql;
            $this->queue_count++;
        }
        if($max > 0 && $this->queue_count >= $max) {
            $this->flushQueue();
        }
    }

    // Function to flush the queue to the database via a MySQL transaction
    public function flushQueue() {
        if(!empty($this->queue)) {
            try{
                // Run the transaction
                $this->db->autocommit(false);
                $this->db->begin_transaction();
                foreach($this->queue as $sql) {
                    $this->query($sql);
                }
                $this->db->commit();
                $this->db->autocommit(true);
                
                // Clear out our queue
                $this->queue = array();
                $this->queue_count = 0;
            } catch (Exception $e) {
                throw new Exception("Error Flushing Queue: " . $e->getMessage());
            }
        }
    }


}
