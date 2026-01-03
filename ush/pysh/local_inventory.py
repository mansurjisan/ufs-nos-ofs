from datetime import datetime
from pathlib import Path
from netCDF4 import Dataset
import logging

logger = logging.getLogger(__name__)

class LocalNWMInventory:
    def __init__(self, filelist, start_date=None, end_date=None):
        """
        Initialize the inventory with local NWM files filtered by time range.

        Parameters:
        - filelist: iterable of local .nc file paths
        - start_date: datetime object, inclusive start of the time window
        - end_date: datetime object, inclusive end of the time window
        """
        self._files = {}

        for f in sorted(filelist):
            try:
                # Open the NetCDF file and read the valid time attribute
                with Dataset(f) as ds:
                    time_str = ds.getncattr("model_output_valid_time")
                timestamp = datetime.strptime(time_str, "%Y-%m-%d_%H:%M:%S")

                # Only include files within the specified time window
                if (start_date is None or timestamp >= start_date) and \
                   (end_date   is None or timestamp <= end_date):
                    self._files[timestamp] = Path(f)
            except Exception as e:
                logger.warning(f"Skipped file {f} due to error: {e}")

        if not self._files:
            raise FileNotFoundError(
                f"No valid NWM files found in the time range {start_date} to {end_date}."
            )

        logger.info(
            f"Loaded {len(self._files)} local NWM files in the time range "
            f"{start_date} to {end_date}."
        )

    @property
    def files(self):
        """Return a dictionary mapping datetime to file Path."""
        return self._files
