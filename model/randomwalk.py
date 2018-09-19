#!/usr/bin/env python
# Copyright 2018 Google LLC
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
import argparse
import csv
import math
import pickle
from os import path, makedirs
from random import randint
from sys import exit, stdout, stderr
from time import sleep

import numpy
import pandas


TRADING_DAYS = 252  # Number of trading days on stock


class DataModel(object):
    def __init__(self, company, start_date):
        self.verbose = False
        self.company = company
        self.start_date = start_date
        self._raw_data = None
        self.data = None
        self.iter_count = 1000
        self.from_csv = None

    def _from_csv(self, file_path):
        data = {}
        with open(file_path, 'rb') as csv_file:
            csv_reader = csv.DictReader(csv_file)
            for line in csv_reader:
                if line['ticker'] == self.company:
                    data[pandas.Timestamp(line['date'])] = line
                    line['Close'] = numpy.float64(line['close'])
                    del line['ticker']
                    del line['date']
        self._raw_data = pandas.DataFrame.from_dict(data, orient='index')

    def _write_csv(self):
        csv_writer = csv.writer(stdout)
        for row in self.data:
            csv_writer.writerow(row)

    def _get_data(self):
        marketd = self._raw_data
        #
        # calculate the compound annual growth rate (CAGR) which will give us 
        # our mean return input (mu)
        #
        days = (marketd.index[-1] - marketd.index[0]).days
        cagr = (marketd['Close'][-1] / marketd['Close'][1]) ** (365.0 / days)-1
        #
        # create a series of percentage returns and calculate the annual 
        # volatility of returns
        #
        marketd['Returns'] = marketd['Close'].pct_change()
        vol = marketd['Returns'].std() * numpy.sqrt(TRADING_DAYS)
        data = []
        starting_price = marketd['Close'][-1]  
        position = randint(10, 1000) * 10
        for i in xrange(self.iter_count):
            daily_returns = numpy.random.normal(cagr / TRADING_DAYS, 
                                                vol / math.sqrt(TRADING_DAYS), 
                                                TRADING_DAYS) + 1
            price_list = [self.company, position, i, starting_price]
            for x in daily_returns:
                price_list.append(price_list[-1] * x)
            data.append(price_list)
        self.data = data

    def run(self):
        if self.from_csv:
            self._from_csv(self.from_csv)
        self._get_data()
        self._write_csv()



def _parse_args():
    parser = argparse.ArgumentParser('randomwalk', 
                                     description='Monte-Carlo simulation of stock prices '
                                                 'behavior based on data from quandl')
    parser.add_argument('-n', 
                        '--snum', 
                        type=int, 
                        default=1000, 
                        help='number of simulations (default:%(default)s)')
    parser.add_argument('-c', 
                        '--company', 
                        required=True, 
                        help='company symbol on stock (i. e. WDC)')
    parser.add_argument('--from-csv', 
                        help='path to wiki csv file')
    parser.add_argument('-s', 
                        '--start-date', 
                        default='2018-01-01', 
                        help='example: %(default)s')
    return parser.parse_args()


def main():
    args = _parse_args()
    data_model = DataModel(args.company, args.start_date)
    data_model.from_csv = args.from_csv
    data_model.run()


if __name__ == '__main__':
    main()
